from pathlib import Path

from reportlab.lib import colors
from reportlab.lib.enums import TA_CENTER
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle, getSampleStyleSheet
from reportlab.lib.units import mm
from reportlab.platypus import KeepTogether, ListFlowable, ListItem, PageBreak, Paragraph, SimpleDocTemplate, Spacer, Table


ROOT = Path(__file__).resolve().parents[1]
DOCUMENTS = [
    (ROOT / "documents/tfp-agreement.md", ROOT / "static/documents/tfp-agreement.pdf"),
    (ROOT / "documents/model-release.md", ROOT / "static/documents/model-release.pdf"),
    (ROOT / "documents/client-release.md", ROOT / "static/documents/client-release.pdf"),
    (ROOT / "documents/privacy-notice.md", ROOT / "static/documents/privacy-notice.pdf"),
]


def build_styles():
    base = getSampleStyleSheet()
    return {
        "title": ParagraphStyle(
            "ContractTitle",
            parent=base["Title"],
            fontName="Helvetica-Bold",
            fontSize=30,
            leading=36,
            textColor=colors.black,
            alignment=TA_CENTER,
            spaceAfter=24,
        ),
        "subtitle": ParagraphStyle(
            "ContractSubtitle",
            parent=base["BodyText"],
            fontName="Helvetica-Bold",
            fontSize=11,
            leading=13,
            textColor=colors.black,
            spaceBefore=0,
            spaceAfter=0,
        ),
        "h2": ParagraphStyle(
            "ContractH2",
            parent=base["Heading2"],
            fontName="Helvetica-Bold",
            fontSize=16,
            leading=19,
            textColor=colors.black,
            spaceBefore=12,
            spaceAfter=5,
        ),
        "h3": ParagraphStyle(
            "ContractH3",
            parent=base["Heading3"],
            fontName="Helvetica-Bold",
            fontSize=10,
            leading=12,
            textColor=colors.black,
            spaceBefore=5,
            spaceAfter=0,
        ),
        "body": ParagraphStyle(
            "ContractBody",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=11,
            leading=12,
            textColor=colors.black,
            spaceAfter=0,
        ),
        "bullet": ParagraphStyle(
            "ContractBullet",
            parent=base["BodyText"],
            fontName="Helvetica",
            fontSize=11,
            leading=12,
            textColor=colors.black,
            spaceAfter=0,
        ),
    }


def inline_markup(text):
    text = text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    parts = text.split("**")
    for index in range(1, len(parts), 2):
        parts[index] = f"<b>{parts[index]}</b>"
    return "".join(parts)


def markdown_to_story(path):
    styles = build_styles()
    story = []
    bullets = []
    table_rows = []
    pending_heading = []
    skip_draft_status = False

    def append_flowable(flowable):
        nonlocal pending_heading
        if pending_heading:
            story.append(KeepTogether([*pending_heading, flowable]))
            pending_heading = []
        else:
            story.append(flowable)

    def append_heading(flowable):
        nonlocal pending_heading
        if pending_heading:
            story.extend(pending_heading)
        pending_heading = [flowable]

    def flush_heading():
        nonlocal pending_heading
        if pending_heading:
            story.extend(pending_heading)
            pending_heading = []

    def flush_bullets():
        nonlocal bullets
        if not bullets:
            return
        append_flowable(
            ListFlowable(
                [ListItem(Paragraph(item, styles["bullet"]), leftIndent=12) for item in bullets],
                bulletType="bullet",
                leftIndent=14,
                bulletFontName="Helvetica",
                bulletFontSize=7.5,
                bulletColor=colors.black,
                spaceBefore=2,
                spaceAfter=4,
            )
        )
        bullets = []

    def flush_table():
        nonlocal table_rows
        if not table_rows:
            return
        content_width = A4[0] - (20 * mm * 2)
        is_signature_table = (
            len(table_rows[0]) == 2
            and len(table_rows) >= 3
            and "Photographer" in table_rows[0][1].getPlainText()
            and any("Signature:" in row[0].getPlainText() for row in table_rows[1:])
        )
        if is_signature_table:
            render_rows = [[row[0], Paragraph("", styles["body"]), row[1]] for row in table_rows]
            col_widths = [content_width * 0.43, content_width * 0.14, content_width * 0.43]
        else:
            render_rows = table_rows
            col_widths = [content_width / len(table_rows[0])] * len(table_rows[0])
        table = Table(render_rows, colWidths=col_widths)
        table.setStyle(
            [
                ("LEFTPADDING", (0, 0), (-1, -1), 0),
                ("RIGHTPADDING", (0, 0), (-1, -1), 0),
                ("TOPPADDING", (0, 0), (-1, -1), 0),
                ("BOTTOMPADDING", (0, 0), (-1, -1), 2),
                ("VALIGN", (0, 0), (-1, -1), "TOP"),
            ]
        )
        append_flowable(table)
        table_rows = []

    for raw_line in path.read_text(encoding="utf-8").splitlines():
        line = raw_line.strip()
        if line in {"\\pagebreak", "<!-- pagebreak -->"}:
            flush_bullets()
            flush_table()
            flush_heading()
            story.append(PageBreak())
            continue
        if line == "## Draft Status":
            flush_bullets()
            flush_table()
            skip_draft_status = True
            continue
        if skip_draft_status:
            if line.startswith("## "):
                skip_draft_status = False
            else:
                continue
        if not line:
            flush_bullets()
            flush_table()
            if not pending_heading:
                append_flowable(Spacer(1, 0))
        elif line.startswith("|") and line.endswith("|"):
            flush_bullets()
            cells = [cell.strip() for cell in line.strip("|").split("|")]
            if all(set(cell) <= {"-", ":"} for cell in cells):
                continue
            style = styles["h3"] if not table_rows else styles["body"]
            table_rows.append([Paragraph(inline_markup(cell), style) for cell in cells])
        elif line.startswith("# "):
            flush_bullets()
            flush_table()
            append_heading(Paragraph(inline_markup(line[2:]), styles["title"]))
        elif line == "Draft/reference document. Not legal advice.":
            continue
        elif line.startswith("## "):
            flush_bullets()
            flush_table()
            append_heading(Paragraph(inline_markup(line[3:].upper()), styles["h2"]))
        elif line.startswith("### "):
            flush_bullets()
            flush_table()
            append_heading(Paragraph(inline_markup(line[4:].upper()), styles["h3"]))
        elif line.endswith(":") and len(line) <= 42:
            flush_bullets()
            flush_table()
            append_heading(Paragraph(inline_markup(line), styles["h3"]))
        elif line.startswith("- "):
            flush_table()
            bullets.append(line[2:])
        else:
            flush_bullets()
            flush_table()
            append_flowable(Paragraph(inline_markup(line), styles["body"]))

    flush_bullets()
    flush_table()
    flush_heading()
    return story


def build_pdf(source, output):
    output.parent.mkdir(parents=True, exist_ok=True)
    document = SimpleDocTemplate(
        str(output),
        pagesize=A4,
        rightMargin=18 * mm,
        leftMargin=18 * mm,
        topMargin=18 * mm,
        bottomMargin=19 * mm,
        title=source.stem.replace("-", " ").title(),
        author="Ignat Kudriavtsev",
    )
    document.build(markdown_to_story(source))


for source_path, output_path in DOCUMENTS:
    build_pdf(source_path, output_path)
    print(output_path)
