import json
import time
from typing import Dict, Any, List, Optional
import aiosqlite
from app.config import ConnectionConfig
from app.core.db_manager import db_manager
from app.core.guardrail import guardrail

class ExplainNode:
    def __init__(
        self,
        node_type: str,
        relation_name: Optional[str] = None,
        total_cost: Optional[float] = None,
        actual_time_ms: Optional[float] = None,
        rows: Optional[int] = None,
        filter_expr: Optional[str] = None,
        index_name: Optional[str] = None,
        detail: Optional[str] = None,
        children: Optional[List["ExplainNode"]] = None
    ):
        self.node_type = node_type
        self.relation_name = relation_name
        self.total_cost = total_cost
        self.actual_time_ms = actual_time_ms
        self.rows = rows
        self.filter_expr = filter_expr
        self.index_name = index_name
        self.detail = detail
        self.children = children or []

    def to_dict(self) -> Dict[str, Any]:
        return {
            "node_type": self.node_type,
            "relation_name": self.relation_name,
            "total_cost": self.total_cost,
            "actual_time_ms": self.actual_time_ms,
            "rows": self.rows,
            "filter_expr": self.filter_expr,
            "index_name": self.index_name,
            "detail": self.detail,
            "children": [c.to_dict() for c in self.children]
        }

class ExplainResult:
    def __init__(
        self,
        engine: str,
        is_analyzed: bool,
        plan_tree: ExplainNode,
        total_cost: Optional[float] = None,
        planning_time_ms: Optional[float] = None,
        execution_time_ms: Optional[float] = None,
        warnings: Optional[List[str]] = None,
        recommendations: Optional[List[str]] = None,
        raw_plan: Any = None,
        error: Optional[str] = None
    ):
        self.engine = engine
        self.is_analyzed = is_analyzed
        self.plan_tree = plan_tree
        self.total_cost = total_cost
        self.planning_time_ms = planning_time_ms
        self.execution_time_ms = execution_time_ms
        self.warnings = warnings or []
        self.recommendations = recommendations or []
        self.raw_plan = raw_plan
        self.error = error

    def to_dict(self) -> Dict[str, Any]:
        return {
            "engine": self.engine,
            "is_analyzed": self.is_analyzed,
            "plan_tree": self.plan_tree.to_dict() if self.plan_tree else None,
            "total_cost": self.total_cost,
            "planning_time_ms": self.planning_time_ms,
            "execution_time_ms": self.execution_time_ms,
            "warnings": self.warnings,
            "recommendations": self.recommendations,
            "raw_plan": self.raw_plan,
            "error": self.error
        }

class ExplainInspector:
    async def explain_query(
        self,
        config: ConnectionConfig,
        sql: str,
        analyze: bool = False
    ) -> ExplainResult:
        dialect = "sqlite" if config.engine == "sqlite" else "postgres"

        # AST Guardrail check: EXPLAIN should be safe
        is_safe, error_msg, _ = guardrail.validate_and_sanitize(
            sql, dialect=dialect, enforce_limit=False
        )
        if not is_safe:
            return ExplainResult(
                engine=config.engine,
                is_analyzed=analyze,
                plan_tree=ExplainNode(node_type="Error"),
                error=error_msg
            )

        if config.engine == "sqlite":
            return await self._explain_sqlite(config, sql)
        elif config.engine == "postgres":
            return await self._explain_postgres(config, sql, analyze)
        else:
            return ExplainResult(
                engine=config.engine,
                is_analyzed=analyze,
                plan_tree=ExplainNode(node_type="Error"),
                error=f"Unsupported engine for EXPLAIN: {config.engine}"
            )

    async def _explain_sqlite(self, config: ConnectionConfig, sql: str) -> ExplainResult:
        if not config.filepath:
            return ExplainResult("sqlite", False, ExplainNode("Error"), error="No SQLite filepath configured")

        explain_sql = f"EXPLAIN QUERY PLAN {sql.strip().rstrip(';')}"
        start_time = time.perf_counter()

        try:
            async with aiosqlite.connect(config.filepath) as db:
                async with db.execute(explain_sql) as cursor:
                    rows = await cursor.fetchall()
                    elapsed = (time.perf_counter() - start_time) * 1000.0

            # Rows format: (id, parent, notused, detail)
            warnings: List[str] = []
            recommendations: List[str] = []
            node_map: Dict[int, ExplainNode] = {}
            child_ids: Dict[int, List[int]] = {}

            for row in rows:
                nid = row[0]
                pid = row[1]
                detail = row[3] if len(row) > 3 else str(row)

                # Heuristic analysis on detail string
                node_type = "Operation"
                relation = None
                index_name = None

                detail_upper = detail.upper()
                if "SCAN" in detail_upper:
                    node_type = "Scan (Full Table Scan)"
                    import re
                    match = re.search(r'SCAN\s+([\w\."`]+)', detail, re.IGNORECASE)
                    if match:
                        relation = match.group(1)
                    warnings.append(f"Full table scan on '{relation or 'table'}': row lookup without index.")
                    recommendations.append(f"Consider creating an index on '{relation or 'table'}' to avoid full scans.")
                elif "SEARCH" in detail_upper:
                    node_type = "Index Search"
                    import re
                    match = re.search(r'SEARCH\s+([\w\."`]+)\s+USING\s+(?:INDEX\s+)?([\w\."`]+)', detail, re.IGNORECASE)
                    if match:
                        relation = match.group(1)
                        index_name = match.group(2)
                elif "USE TEMP B-TREE" in detail_upper:
                    node_type = "Temporary B-Tree"
                    warnings.append("Using temporary in-memory B-Tree for sorting/grouping.")
                    recommendations.append("Consider indexing columns used in ORDER BY or GROUP BY.")

                node = ExplainNode(
                    node_type=node_type,
                    relation_name=relation,
                    index_name=index_name,
                    detail=detail
                )
                node_map[nid] = node
                child_ids.setdefault(pid, []).append(nid)

            # Build tree hierarchy
            root_children = []
            for nid, node in node_map.items():
                if nid in child_ids:
                    node.children = [node_map[cid] for cid in child_ids[nid] if cid in node_map]

            root_nodes = [node_map[nid] for nid in child_ids.get(0, []) if nid in node_map]
            if not root_nodes and node_map:
                root_nodes = list(node_map.values())

            root = ExplainNode(
                node_type="Query Root",
                detail="SQLite Query Execution Plan",
                children=root_nodes
            ) if len(root_nodes) > 1 else (root_nodes[0] if root_nodes else ExplainNode("Empty Plan"))

            return ExplainResult(
                engine="sqlite",
                is_analyzed=False,
                plan_tree=root,
                planning_time_ms=round(elapsed, 2),
                warnings=list(dict.fromkeys(warnings)),
                recommendations=list(dict.fromkeys(recommendations)),
                raw_plan=[list(r) for r in rows]
            )
        except Exception as e:
            return ExplainResult("sqlite", False, ExplainNode("Error"), error=f"SQLite EXPLAIN failed: {str(e)}")

    async def _explain_postgres(
        self,
        config: ConnectionConfig,
        sql: str,
        analyze: bool = False
    ) -> ExplainResult:
        pool = await db_manager.get_pg_pool(config)
        clean_sql = sql.strip().rstrip(";")

        if analyze:
            explain_cmd = f"EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON) {clean_sql}"
        else:
            explain_cmd = f"EXPLAIN (COSTS, VERBOSE, FORMAT JSON) {clean_sql}"

        start_time = time.perf_counter()
        auto_cast_applied = False
        try:
            async with pool.acquire() as conn:
                try:
                    raw_res = await conn.fetchval(explain_cmd)
                except Exception as e:
                    err_msg = str(e).lower()
                    if "operator does not exist" in err_msg or "cannot be matched" in err_msg:
                        casted_sql = db_manager._auto_cast_mismatched_sql(clean_sql)
                        if casted_sql != clean_sql:
                            auto_cast_applied = True
                            if analyze:
                                retry_cmd = f"EXPLAIN (ANALYZE, COSTS, VERBOSE, BUFFERS, FORMAT JSON) {casted_sql}"
                            else:
                                retry_cmd = f"EXPLAIN (COSTS, VERBOSE, FORMAT JSON) {casted_sql}"
                            raw_res = await conn.fetchval(retry_cmd)
                        else:
                            raise e
                    else:
                        raise e
                elapsed = (time.perf_counter() - start_time) * 1000.0

            parsed = json.loads(raw_res) if isinstance(raw_res, str) else raw_res
            if not parsed or not isinstance(parsed, list):
                return ExplainResult("postgres", analyze, ExplainNode("Empty"), error="No plan returned")

            plan_dict = parsed[0]
            root_plan = plan_dict.get("Plan", {})
            planning_time = plan_dict.get("Planning Time", round(elapsed, 2))
            execution_time = plan_dict.get("Execution Time")

            warnings: List[str] = []
            recommendations: List[str] = []

            if auto_cast_applied:
                warnings.append("Datatype mismatch detected: Automatic type casting (::text) was applied to comparison predicates.")
                recommendations.append("Add explicit type casts (e.g. CAST(col AS smallint) or col::smallint) to your query predicates to allow index utilization.")

            def _parse_pg_node(node_data: Dict[str, Any]) -> ExplainNode:
                ntype = node_data.get("Node Type", "Unknown")
                rel = node_data.get("Relation Name")
                cost = node_data.get("Total Cost")
                time_ms = node_data.get("Actual Total Time")
                rows = node_data.get("Actual Rows") or node_data.get("Plan Rows")
                filt = node_data.get("Filter")
                idx = node_data.get("Index Name")

                if ntype == "Seq Scan":
                    warnings.append(f"Sequential Scan on table '{rel or 'table'}'.")
                    if filt:
                        recommendations.append(f"Add index on '{rel}' matching filter: {filt}")
                    else:
                        recommendations.append(f"Consider indexing lookup columns on '{rel}'.")
                elif "Nested Loop" in ntype and (cost and cost > 1000.0):
                    warnings.append(f"High-cost Nested Loop Join (cost: {cost}).")
                    recommendations.append("Verify join keys have indexes on both tables.")

                children = []
                for sub in node_data.get("Plans", []):
                    children.append(_parse_pg_node(sub))

                return ExplainNode(
                    node_type=ntype,
                    relation_name=rel,
                    total_cost=cost,
                    actual_time_ms=time_ms,
                    rows=rows,
                    filter_expr=filt,
                    index_name=idx,
                    children=children
                )

            plan_tree = _parse_pg_node(root_plan)

            return ExplainResult(
                engine="postgres",
                is_analyzed=analyze,
                plan_tree=plan_tree,
                total_cost=root_plan.get("Total Cost"),
                planning_time_ms=planning_time,
                execution_time_ms=execution_time,
                warnings=list(dict.fromkeys(warnings)),
                recommendations=list(dict.fromkeys(recommendations)),
                raw_plan=parsed
            )
        except Exception as e:
            return ExplainResult("postgres", analyze, ExplainNode("Error"), error=f"PostgreSQL EXPLAIN failed: {str(e)}")

explain_inspector = ExplainInspector()
