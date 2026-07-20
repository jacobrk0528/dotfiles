"""Custom layout rules for jkrebs's house SQL style."""

from typing import Optional

from sqlfluff.core.parser import NewlineSegment
from sqlfluff.core.plugin import hookimpl
from sqlfluff.core.rules import BaseRule, LintFix, LintResult, RuleContext
from sqlfluff.core.rules.crawlers import SegmentSeekerCrawler


@hookimpl
def get_rules() -> list[type[BaseRule]]:
    """Get plugin rules.

    NOTE: The rule class is defined and imported here, rather than at
    module scope, per SQLFluff's plugin guidance: defining it before all
    plugins are loaded triggers "imported too early" warnings.
    """

    class Rule_TrinityRoad_TR01(BaseRule):
        """``AND``/``OR`` should always start a new line.

        Stock SQLFluff only breaks boolean operators onto their own line
        once the clause exceeds ``max_line_length``. This rule forces the
        break unconditionally, regardless of line length, so ``WHERE``
        clauses are always fully expanded.

        **Anti-pattern**

        .. code-block:: sql

            SELECT * FROM xyz WHERE a = b AND c = d

        **Best practice**

        .. code-block:: sql

            SELECT
                *
            FROM xyz
            WHERE
                a = b
                AND c = d
        """

        name = "layout.boolean_operator_newline"
        groups = ("all", "layout")
        crawl_behaviour = SegmentSeekerCrawler({"binary_operator"})
        is_fix_compatible = True

        def _eval(self, context: RuleContext) -> Optional[LintResult]:
            segment = context.segment
            if segment.raw_upper not in ("AND", "OR"):
                return None
            if not context.parent_stack:
                return None

            parent = context.parent_stack[-1]
            siblings = parent.segments
            idx = siblings.index(segment)

            # Walk backwards over whitespace/comments looking for an
            # existing newline. If real content comes first, it needs one.
            for prev in siblings[idx - 1 :: -1]:
                if prev.is_type("newline"):
                    return None
                if not prev.is_type("whitespace", "indent", "dedent", "comment"):
                    break

            return LintResult(
                anchor=segment,
                description=(
                    f"'{segment.raw_upper}' should always start a new line."
                ),
                fixes=[LintFix.create_before(segment, [NewlineSegment()])],
            )

    return [Rule_TrinityRoad_TR01]
