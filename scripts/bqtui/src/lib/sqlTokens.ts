// A small, forgiving SQL tokenizer used for editor syntax highlighting.
// It is deliberately not a parser: it only needs to classify spans.

export type TokenKind =
  | "keyword"
  | "type"
  | "function"
  | "string"
  | "number"
  | "comment"
  | "identifier"
  | "operator"
  | "punct"
  | "variable";

export interface Token {
  kind: TokenKind;
  start: number; // inclusive char offset
  end: number; // exclusive char offset
}

const KEYWORDS = new Set(
  `ALL AND ANY ARRAY AS ASC ASSERT_ROWS_MODIFIED AT BEGIN BETWEEN BREAK BY CALL CASE CAST CLUSTER COLLATE
   CONTAINS CONTINUE CREATE CROSS CUBE CURRENT DECLARE DEFAULT DEFINE DELETE DESC DISTINCT DROP ELSE END ENUM
   ESCAPE EXCEPT EXCLUDE EXECUTE EXISTS EXPORT EXTRACT FALSE FETCH FOLLOWING FOR FROM FULL FUNCTION GRANT GROUP GROUPING
   GROUPS HASH HAVING IF IGNORE IMMEDIATE IN INNER INSERT INTERSECT INTERVAL INTO IS ITERATE JOIN LATERAL LEAVE LEFT
   LIKE LIMIT LOOKUP LOOP MATERIALIZED MERGE NATURAL NEW NO NOT NULL NULLS OF ON OPTIONS OR ORDER OUTER OVER PARTITION
   PRECEDING PROC PROCEDURE PROTO QUALIFY RANGE RECURSIVE REPEAT REPLACE RESPECT RETURNS RIGHT ROLLUP ROWS SAFE_CAST SCHEMA
   SELECT SET SOME STRUCT SYSTEM TABLE TABLESAMPLE TEMP TEMPORARY THEN TO TREAT TRUE TRUNCATE UNBOUNDED UNION UNNEST UPDATE
   USING VALUES VIEW WHEN WHERE WHILE WINDOW WITH WITHIN PIVOT UNPIVOT RETURN ELSEIF RAISE EXCEPTION OPTION PRIMARY KEY
   ALTER ADD COLUMN COLUMNS RENAME EXPLAIN INFORMATION_SCHEMA`
    .split(/\s+/)
    .filter(Boolean),
);

const TYPES = new Set(
  `STRING BYTES INT64 INTEGER INT SMALLINT BIGINT TINYINT BYTEINT FLOAT64 FLOAT NUMERIC DECIMAL BIGNUMERIC BIGDECIMAL
   BOOL BOOLEAN DATE DATETIME TIME TIMESTAMP GEOGRAPHY JSON RECORD ARRAY STRUCT INTERVAL RANGE`
    .split(/\s+/)
    .filter(Boolean),
);

function isIdentStart(c: string): boolean {
  return /[A-Za-z_]/.test(c);
}
function isIdentChar(c: string): boolean {
  return /[A-Za-z0-9_]/.test(c);
}
function isDigit(c: string): boolean {
  return /[0-9]/.test(c);
}

export function tokenizeSql(src: string): Token[] {
  const tokens: Token[] = [];
  const n = src.length;
  let i = 0;

  const push = (kind: TokenKind, start: number, end: number) => {
    if (end > start) tokens.push({ kind, start, end });
  };

  while (i < n) {
    const c = src[i]!;
    const next = src[i + 1] ?? "";

    // whitespace
    if (/\s/.test(c)) {
      i++;
      continue;
    }

    // comments
    if (c === "-" && next === "-") {
      const start = i;
      while (i < n && src[i] !== "\n") i++;
      push("comment", start, i);
      continue;
    }
    if (c === "#") {
      const start = i;
      while (i < n && src[i] !== "\n") i++;
      push("comment", start, i);
      continue;
    }
    if (c === "/" && next === "*") {
      const start = i;
      const close = src.indexOf("*/", i + 2);
      i = close === -1 ? n : close + 2;
      push("comment", start, i);
      continue;
    }

    // backtick identifiers
    if (c === "`") {
      const start = i;
      const close = src.indexOf("`", i + 1);
      i = close === -1 ? n : close + 1;
      push("identifier", start, i);
      continue;
    }

    // strings: optional r/b prefix, triple or single quotes
    if (
      c === "'" ||
      c === '"' ||
      ((c === "r" || c === "R" || c === "b" || c === "B") && (next === "'" || next === '"')) ||
      ((c === "r" || c === "R" || c === "b" || c === "B") &&
        (next === "b" || next === "B" || next === "r" || next === "R") &&
        (src[i + 2] === "'" || src[i + 2] === '"'))
    ) {
      const start = i;
      while (i < n && src[i] !== "'" && src[i] !== '"') i++;
      const q = src[i]!;
      const triple = src.startsWith(q.repeat(3), i);
      if (triple) {
        const close = src.indexOf(q.repeat(3), i + 3);
        i = close === -1 ? n : close + 3;
      } else {
        i++;
        while (i < n && src[i] !== q) {
          if (src[i] === "\\") i++;
          if (src[i] === "\n") break;
          i++;
        }
        if (i < n && src[i] === q) i++;
      }
      push("string", start, i);
      continue;
    }

    // numbers
    if (isDigit(c) || (c === "." && isDigit(next))) {
      const start = i;
      if (c === "0" && (next === "x" || next === "X")) {
        i += 2;
        while (i < n && /[0-9a-fA-F]/.test(src[i]!)) i++;
      } else {
        while (i < n && (isDigit(src[i]!) || src[i] === ".")) i++;
        if (i < n && (src[i] === "e" || src[i] === "E")) {
          i++;
          if (src[i] === "+" || src[i] === "-") i++;
          while (i < n && isDigit(src[i]!)) i++;
        }
      }
      push("number", start, i);
      continue;
    }

    // @variables / @@system variables
    if (c === "@") {
      const start = i;
      i++;
      while (i < n && (isIdentChar(src[i]!) || src[i] === "@")) i++;
      push("variable", start, i);
      continue;
    }

    // identifiers / keywords / functions
    if (isIdentStart(c)) {
      const start = i;
      while (i < n && isIdentChar(src[i]!)) i++;
      const word = src.slice(start, i);
      const upper = word.toUpperCase();
      // look ahead for "(" to classify functions
      let j = i;
      while (j < n && (src[j] === " " || src[j] === "\t")) j++;
      const callsFn = src[j] === "(";
      if (TYPES.has(upper) && !callsFn) push("type", start, i);
      else if (KEYWORDS.has(upper)) push("keyword", start, i);
      else if (callsFn) push("function", start, i);
      else push("identifier", start, i);
      continue;
    }

    // operators & punctuation
    if ("<>=!|&+-*/%^~".includes(c)) {
      const start = i;
      i++;
      while (i < n && "<>=|&".includes(src[i]!) && i - start < 3) i++;
      push("operator", start, i);
      continue;
    }
    push("punct", i, i + 1);
    i++;
  }
  return tokens;
}
