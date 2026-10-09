import '../models/table_schema.dart';

enum SqlSuggestionType {
  keyword,
  table,
  column,
  subquery,
  function,
  parameter,
}

class SqlSuggestion {
  final String insertText;
  final String displayText;
  final SqlSuggestionType type;
  final String? detail;
  final int cursorOffsetFromEnd;

  const SqlSuggestion({
    required this.insertText,
    required this.displayText,
    required this.type,
    this.detail,
    this.cursorOffsetFromEnd = 0,
  });
}

class SqlSubquerySnippet {
  final String title;
  final String description;
  final String template;
  final String category;

  const SqlSubquerySnippet({
    required this.title,
    required this.description,
    required this.template,
    required this.category,
  });
}

class SqlAutocompleteService {
  static const List<String> sqlKeywords = [
    'SELECT', 'DISTINCT', 'FROM', 'WHERE', 'JOIN', 'LEFT JOIN', 'RIGHT JOIN',
    'INNER JOIN', 'FULL OUTER JOIN', 'CROSS JOIN', 'ON', 'AS', 'AND', 'OR', 'NOT',
    'GROUP BY', 'HAVING', 'ORDER BY', 'ASC', 'DESC', 'LIMIT', 'OFFSET',
    'WITH', 'RECURSIVE', 'UNION', 'UNION ALL', 'INTERSECT', 'EXCEPT',
    'IN', 'EXISTS', 'BETWEEN', 'LIKE', 'ILIKE', 'IS NULL', 'IS NOT NULL',
    'CASE', 'WHEN', 'THEN', 'ELSE', 'END', 'OVER', 'PARTITION BY',
    'INSERT INTO', 'VALUES', 'UPDATE', 'SET', 'DELETE FROM', 'CREATE TABLE',
    'DROP TABLE', 'ALTER TABLE', 'TRUNCATE', 'EXPLAIN', 'ANALYZE'
  ];

  static const List<String> sqlFunctions = [
    'COUNT(*)', 'COUNT()', 'SUM()', 'AVG()', 'MIN()', 'MAX()',
    'COALESCE()', 'NULLIF()', 'CONCAT()', 'SUBSTRING()', 'TRIM()',
    'LOWER()', 'UPPER()', 'NOW()', 'CURRENT_DATE', 'CURRENT_TIMESTAMP',
    'DATE()', 'EXTRACT()', 'AGE()', 'ROW_NUMBER() OVER ()',
    'RANK() OVER ()', 'DENSE_RANK() OVER ()'
  ];

  static const List<SqlSubquerySnippet> subquerySnippets = [
    SqlSubquerySnippet(
      title: 'WHERE IN (Subquery)',
      description: 'Filter rows matching values from an inner query',
      category: 'Filtering',
      template: 'WHERE column_name IN (\n  SELECT column_name\n  FROM sub_table\n  WHERE sub_condition\n)',
    ),
    SqlSubquerySnippet(
      title: 'WHERE NOT IN (Subquery)',
      description: 'Exclude rows matching values from an inner query',
      category: 'Filtering',
      template: 'WHERE column_name NOT IN (\n  SELECT column_name\n  FROM sub_table\n  WHERE sub_condition\n)',
    ),
    SqlSubquerySnippet(
      title: 'WHERE EXISTS (Subquery)',
      description: 'Check for the existence of rows in a correlated subquery',
      category: 'Filtering',
      template: 'WHERE EXISTS (\n  SELECT 1\n  FROM sub_table st\n  WHERE st.foreign_id = main_table.id\n)',
    ),
    SqlSubquerySnippet(
      title: 'WHERE NOT EXISTS (Subquery)',
      description: 'Filter for records that have no matching records in another table',
      category: 'Filtering',
      template: 'WHERE NOT EXISTS (\n  SELECT 1\n  FROM sub_table st\n  WHERE st.foreign_id = main_table.id\n)',
    ),
    SqlSubquerySnippet(
      title: 'WITH CTE (Common Table Expression)',
      description: 'Define a temporary named result set to simplify complex queries',
      category: 'CTE / Modular',
      template: 'WITH cte_summary AS (\n  SELECT \n    category_id,\n    COUNT(*) AS total_items,\n    AVG(price) AS avg_price\n  FROM items\n  GROUP BY category_id\n)\nSELECT \n  c.category_name,\n  s.total_items,\n  s.avg_price\nFROM categories c\nJOIN cte_summary s ON c.id = s.category_id;',
    ),
    SqlSubquerySnippet(
      title: 'Multiple CTEs (Chained WITH)',
      description: 'Chain multiple Common Table Expressions together',
      category: 'CTE / Modular',
      template: 'WITH raw_data AS (\n  SELECT * FROM orders WHERE status = :status\n),\naggregated AS (\n  SELECT user_id, SUM(total) AS spend FROM raw_data GROUP BY user_id\n)\nSELECT u.username, a.spend\nFROM users u\nJOIN aggregated a ON u.id = a.user_id\nORDER BY a.spend DESC;',
    ),
    SqlSubquerySnippet(
      title: 'Scalar Subquery in SELECT',
      description: 'Fetch a single calculated value for each row',
      category: 'Projection',
      template: 'SELECT \n  t.id,\n  t.name,\n  (\n    SELECT COUNT(*)\n    FROM related_items r\n    WHERE r.parent_id = t.id\n  ) AS item_count\nFROM parent_table t;',
    ),
    SqlSubquerySnippet(
      title: 'Derived Table in FROM / JOIN',
      description: 'Join with a subquery as a virtual table',
      category: 'Joins',
      template: 'JOIN (\n  SELECT user_id, MAX(created_at) AS latest_activity\n  FROM activity_logs\n  GROUP BY user_id\n) latest ON latest.user_id = u.id',
    ),
    SqlSubquerySnippet(
      title: 'Window Function OVER (PARTITION BY)',
      description: 'Perform analytical calculations across rows related to the current row',
      category: 'Analytics',
      template: 'COUNT(*) OVER (PARTITION BY category_id) AS items_in_category',
    ),
    SqlSubquerySnippet(
      title: 'Conditional CASE WHEN Expression',
      description: 'Multi-branch conditional logic inside SELECT or WHERE',
      category: 'Expressions',
      template: 'CASE \n  WHEN status = 1 THEN \'Active\'\n  WHEN status = 2 THEN \'Pending\'\n  ELSE \'Inactive\'\nEND AS status_label',
    ),
  ];

  /// Returns contextual suggestions based on current query text, cursor position, and schema.
  List<SqlSuggestion> getSuggestions({
    required String text,
    required int cursorPosition,
    required List<TableMetadata> tables,
  }) {
    if (cursorPosition < 0 || cursorPosition > text.length) {
      return [];
    }

    // Extract text up to cursor
    final textBeforeCursor = text.substring(0, cursorPosition);
    if (textBeforeCursor.trim().isEmpty) {
      // Empty editor: suggest standard starting keywords and CTE
      return [
        const SqlSuggestion(
          insertText: 'SELECT ',
          displayText: 'SELECT',
          type: SqlSuggestionType.keyword,
          detail: 'Start query',
        ),
        const SqlSuggestion(
          insertText: 'WITH cte AS (\n  SELECT *\n  FROM table_name\n)\nSELECT * FROM cte;',
          displayText: 'WITH (CTE)',
          type: SqlSuggestionType.subquery,
          detail: 'Common Table Expression',
        ),
        const SqlSuggestion(
          insertText: 'EXPLAIN ANALYZE SELECT ',
          displayText: 'EXPLAIN ANALYZE',
          type: SqlSuggestionType.keyword,
          detail: 'Query performance profile',
        ),
      ];
    }

    // Find current word/token being typed
    final wordMatch = RegExp(r'([a-zA-Z0-9_.:]+)$').firstMatch(textBeforeCursor);
    final currentWord = wordMatch?.group(1) ?? '';
    final lowerWord = currentWord.toLowerCase();

    // Check if user is typing a dot accessor (e.g. "u." or "users." or "public.users.")
    if (currentWord.contains('.')) {
      final parts = currentWord.split('.');
      final qualifier = parts.first.toLowerCase();
      final columnPrefix = parts.length > 1 ? parts.last.toLowerCase() : '';

      // Find matching table or alias
      TableMetadata? matchedTable;
      for (final table in tables) {
        if (table.rawName.toLowerCase() == qualifier ||
            table.name.toLowerCase() == qualifier ||
            table.rawName.toLowerCase().startsWith(qualifier)) {
          matchedTable = table;
          break;
        }
      }

      // Also check if qualifier is an alias used in the query
      matchedTable ??= _findTableForAlias(textBeforeCursor, qualifier, tables);

      if (matchedTable != null) {
        return matchedTable.columns
            .where((col) => col.name.toLowerCase().contains(columnPrefix))
            .map((col) => SqlSuggestion(
                  insertText: col.name,
                  displayText: '${col.name} (${col.dataType})',
                  type: SqlSuggestionType.column,
                  detail: '${matchedTable!.rawName}.${col.name}',
                ))
            .toList();
      }
    }

    // Check if the preceding clause suggests a TABLE (after FROM, JOIN, INTO, TABLE, UPDATE)
    final trimmedPreceding = textBeforeCursor.substring(0, textBeforeCursor.length - currentWord.length).trimRight();
    final isAfterFromOrJoin = RegExp(
      r'\b(FROM|JOIN|LEFT\s+JOIN|RIGHT\s+JOIN|INNER\s+JOIN|CROSS\s+JOIN|INTO|UPDATE)\s*$',
      caseSensitive: false,
    ).hasMatch(trimmedPreceding);

    final isDirectlyAfterJoin = RegExp(
      r'\b(JOIN|LEFT\s+JOIN|RIGHT\s+JOIN|INNER\s+JOIN|CROSS\s+JOIN)\s*$',
      caseSensitive: false,
    ).hasMatch(trimmedPreceding);

    final List<SqlSuggestion> results = [];

    // Smart Relational JOIN suggestions (FK-aware)
    if (isDirectlyAfterJoin) {
      final activeTables = _detectTablesInQuery(textBeforeCursor, tables);
      for (final activeT in activeTables) {
        // Direct foreign keys: table.fk -> targetTable.id
        for (final fk in activeT.foreignKeys) {
          if (fk.targetTable.toLowerCase().contains(lowerWord) || lowerWord.isEmpty) {
            results.add(SqlSuggestion(
              insertText: '${fk.targetTable} ON ${activeT.rawName}.${fk.columnName} = ${fk.targetTable}.${fk.targetColumn}',
              displayText: 'JOIN ${fk.targetTable} (via ${fk.columnName})',
              type: SqlSuggestionType.subquery,
              detail: 'Relational FK: ${activeT.rawName}.${fk.columnName} -> ${fk.targetTable}.${fk.targetColumn}',
            ));
          }
        }
        // Reverse foreign keys: otherTable.fk -> table.id
        for (final otherT in tables) {
          if (otherT.rawName.toLowerCase() == activeT.rawName.toLowerCase()) continue;
          for (final fk in otherT.foreignKeys) {
            if (fk.targetTable.toLowerCase() == activeT.rawName.toLowerCase()) {
              if (otherT.rawName.toLowerCase().contains(lowerWord) || lowerWord.isEmpty) {
                results.add(SqlSuggestion(
                  insertText: '${otherT.rawName} ON ${otherT.rawName}.${fk.columnName} = ${activeT.rawName}.${fk.targetColumn}',
                  displayText: 'JOIN ${otherT.rawName} (FK -> ${activeT.rawName})',
                  type: SqlSuggestionType.subquery,
                  detail: 'Incoming FK: ${otherT.rawName}.${fk.columnName} -> ${activeT.rawName}.${fk.targetColumn}',
                ));
              }
            }
          }
        }
      }
    }

    // 1. Table suggestions
    if (isAfterFromOrJoin || lowerWord.length >= 2) {
      for (final table in tables) {
        if (lowerWord.isEmpty || table.rawName.toLowerCase().contains(lowerWord) || table.name.toLowerCase().contains(lowerWord)) {
          results.add(SqlSuggestion(
            insertText: table.rawName,
            displayText: table.name,
            type: SqlSuggestionType.table,
            detail: 'Table (${table.columns.length} columns)',
          ));
        }
      }
    }

    // 2. Column suggestions from tables detected in the query
    final tablesInQuery = _detectTablesInQuery(text, tables);
    if (!isAfterFromOrJoin) {
      for (final table in tablesInQuery) {
        for (final col in table.columns) {
          if (lowerWord.isEmpty || col.name.toLowerCase().contains(lowerWord)) {
            results.add(SqlSuggestion(
              insertText: col.name,
              displayText: col.name,
              type: SqlSuggestionType.column,
              detail: '${table.rawName} (${col.dataType})',
            ));
          }
        }
      }
    }

    // 3. Subquery & CTE snippet suggestions
    if (lowerWord.isNotEmpty) {
      for (final snippet in subquerySnippets) {
        if (snippet.title.toLowerCase().contains(lowerWord) ||
            snippet.description.toLowerCase().contains(lowerWord) ||
            snippet.category.toLowerCase().contains(lowerWord)) {
          results.add(SqlSuggestion(
            insertText: snippet.template,
            displayText: snippet.title,
            type: SqlSuggestionType.subquery,
            detail: snippet.description,
          ));
        }
      }
    }

    // 4. SQL Keywords
    if (lowerWord.isNotEmpty) {
      for (final kw in sqlKeywords) {
        if (kw.toLowerCase().startsWith(lowerWord) || kw.toLowerCase().contains(lowerWord)) {
          results.add(SqlSuggestion(
            insertText: '$kw ',
            displayText: kw,
            type: SqlSuggestionType.keyword,
            detail: 'SQL Keyword',
          ));
        }
      }
    }

    // 5. Common SQL functions
    if (lowerWord.isNotEmpty) {
      for (final fn in sqlFunctions) {
        if (fn.toLowerCase().contains(lowerWord)) {
          results.add(SqlSuggestion(
            insertText: fn,
            displayText: fn,
            type: SqlSuggestionType.function,
            detail: 'Function',
          ));
        }
      }
    }

    // 6. Parameter suggestions if user typed ":"
    if (currentWord.startsWith(':')) {
      final detectedParams = extractParameters(text);
      for (final p in detectedParams) {
        results.add(SqlSuggestion(
          insertText: ':$p',
          displayText: ':$p',
          type: SqlSuggestionType.parameter,
          detail: 'Query Parameter',
        ));
      }
      if (!results.any((s) => s.type == SqlSuggestionType.parameter)) {
        results.add(const SqlSuggestion(
          insertText: ':param',
          displayText: ':param',
          type: SqlSuggestionType.parameter,
          detail: 'New Parameter',
        ));
      }
    }

    return results.take(15).toList();
  }

  /// Finds the TableMetadata corresponding to an alias in the query (e.g., `users u` -> `u` maps to `users`).
  TableMetadata? _findTableForAlias(String queryBeforeCursor, String alias, List<TableMetadata> tables) {
    final pattern = RegExp(r'\b([a-zA-Z0-9_]+)\s+(?:AS\s+)?' + RegExp.escape(alias) + r'\b', caseSensitive: false);
    final match = pattern.firstMatch(queryBeforeCursor);
    if (match != null) {
      final rawTableName = match.group(1)!.toLowerCase();
      for (final table in tables) {
        if (table.rawName.toLowerCase() == rawTableName || table.name.toLowerCase() == rawTableName) {
          return table;
        }
      }
    }
    return null;
  }

  /// Identifies all tables referenced anywhere in the query string.
  List<TableMetadata> _detectTablesInQuery(String query, List<TableMetadata> tables) {
    final lowerQuery = query.toLowerCase();
    final matched = <TableMetadata>[];
    for (final t in tables) {
      if (lowerQuery.contains(t.rawName.toLowerCase()) || lowerQuery.contains(t.name.toLowerCase())) {
        matched.add(t);
      }
    }
    return matched.isEmpty ? tables : matched;
  }

  /// Extracts parameter variable names like `:user_id`, `$1`, `?` from a SQL query.
  List<String> extractParameters(String sql) {
    final params = <String>{};
    // Match named parameters: :param_name
    final namedMatches = RegExp(r':([a-zA-Z0-9_]+)').allMatches(sql);
    for (final m in namedMatches) {
      params.add(m.group(1)!);
    }
    // Match postgres style: $1, $2
    final pgMatches = RegExp(r'\$([0-9]+)').allMatches(sql);
    for (final m in pgMatches) {
      params.add('\$${m.group(1)}');
    }
    // Match question marks
    if (sql.contains('?')) {
      params.add('?');
    }
    return params.toList();
  }

  /// Formats SQL with standard uppercase keywords and clean indentation.
  String formatSql(String rawSql) {
    if (rawSql.trim().isEmpty) return rawSql;

    var formatted = rawSql.trim();

    // Standardize keywords to UPPERCASE
    const majorKeywords = [
      'select', 'distinct', 'from', 'where', 'and', 'or', 'join', 'left join',
      'right join', 'inner join', 'cross join', 'group by', 'having', 'order by',
      'limit', 'offset', 'with', 'as', 'union', 'union all', 'case', 'when',
      'then', 'else', 'end', 'on', 'in', 'exists', 'not', 'asc', 'desc'
    ];

    for (final kw in majorKeywords) {
      final regex = RegExp('\\b$kw\\b', caseSensitive: false);
      formatted = formatted.replaceAllMapped(regex, (m) => kw.toUpperCase());
    }

    // Add newlines before major query clauses if they aren't on their own lines
    const breakKeywords = [
      'FROM', 'WHERE', 'GROUP BY', 'HAVING', 'ORDER BY', 'LIMIT',
      'LEFT JOIN', 'RIGHT JOIN', 'INNER JOIN', 'JOIN', 'UNION'
    ];

    for (final kw in breakKeywords) {
      final regex = RegExp('(?<!^|\n)\\s+($kw)\\b');
      formatted = formatted.replaceAllMapped(regex, (m) => '\n${m.group(1)}');
    }

    return formatted;
  }
}
