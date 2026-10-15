#!/usr/bin/env python3
"""Generate UNZA Z CHAT final-year project report (.docx) and defence (.pptx)."""

from __future__ import annotations

from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH, WD_LINE_SPACING
from docx.oxml.ns import qn
from docx.shared import Inches, Pt, RGBColor, Cm
from pptx import Presentation
from pptx.dml.color import RGBColor
from pptx.enum.text import PP_ALIGN
from pptx.enum.shapes import MSO_SHAPE
from pptx.util import Inches as PInches, Pt as PPt, Emu

DESKTOP = Path(r"c:\Users\user\Desktop")
REPORT_PATH = DESKTOP / "UnZA_Z_CHAT_Final_Year_Project_Report.docx"
PPT_PATH = DESKTOP / "UnZA_Z_CHAT_Project_Defence.pptx"
TEMPLATE_PPT = Path(
    r"c:\Users\user\Downloads\Final Year Project Defence - Template (Computer Science 4th Years Projects).pptx"
)
LOGO = Path(r"c:\Users\user\Downloads\unza logo.png")

# ── Contribution split (equal thirds) ────────────────────────────────────────
INNOCENT = {
    "name": "Innocent Tembo",
    "id": "2022003055",
    "role": "Group Coordinator; Messaging, Real-time Communication & Campus Social Modules",
    "modules": [
        "One-to-one and group messaging (ChatService, chat list/screen, starred messages)",
        "AES-256-CBC per-chat message encryption (EncryptionService)",
        "Communities and community detail flows (CommunitiesService)",
        "Status updates (StatusService) and presence (PresenceService)",
        "Voice/video calls and call history (CallService, ZegoService, incoming/outgoing UI)",
        "Broadcast lists (BroadcastService)",
        "Chat media, location sharing, GIF picker integration, and related navigation",
    ],
}
RUTH = {
    "name": "Ruth Kamwendo",
    "id": "________",
    "role": "Academic Resources, Courses, Planner & Classroom Modules",
    "modules": [
        "Course catalogue and enrolment (CoursesService, UNZA program data)",
        "Past paper upload, listing, verification, and PDF open/download (PapersService)",
        "Exam simulator and adaptive learning path screens",
        "Study planner: timetable, study plans/guides, local reminders (PlannerService)",
        "Virtual classroom scheduling and live session screens (Classroom / LiveSession)",
        "Lecturer academic surfaces (courses, classroom, planner streams)",
        "Offline-oriented auto-download helpers for study materials",
    ],
}
KEWA = {
    "name": "Kewa Lupeke",
    "id": "________",
    "role": "AI Study Companion, Authentication/Backend Integration, Forums & Deployment",
    "modules": [
        "Phone OTP authentication bridged to Firebase custom tokens (AuthService)",
        "External Node.js backend integration for OTP, AI, and notifications (AppConfig)",
        "AI assistant: chat, streaming, quizzes, summaries, group summarizer, insights (AiService)",
        "Voice assistant overlay and speech intents (VoiceAssistantService)",
        "ZFeed / Threads forums: posts, comments, bookmarks, search (ThreadsService)",
        "FCM push notifications and two-step / profile security helpers",
        "Build/deploy configuration (Codemagic, dart-define secrets, Firebase project wiring)",
    ],
}


def set_run_font(run, name="Times New Roman", size=12, bold=False, italic=False):
    run.font.name = name
    run._element.rPr.rFonts.set(qn("w:eastAsia"), name)
    run.font.size = Pt(size)
    run.bold = bold
    run.italic = italic


def add_para(doc, text, style=None, bold=False, size=12, align="left", space_after=8, first_indent=False):
    p = doc.add_paragraph(style=style) if style else doc.add_paragraph()
    if align == "center":
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER
    elif align == "justify":
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
    elif align == "right":
        p.alignment = WD_ALIGN_PARAGRAPH.RIGHT
    if first_indent:
        p.paragraph_format.first_line_indent = Cm(1.27)
    p.paragraph_format.space_after = Pt(space_after)
    p.paragraph_format.line_spacing_rule = WD_LINE_SPACING.ONE_POINT_FIVE
    run = p.add_run(text)
    set_run_font(run, size=size, bold=bold)
    return p


def add_heading(doc, text, level=1):
    h = doc.add_heading(text, level=level)
    for run in h.runs:
        set_run_font(run, size=14 if level == 1 else 13 if level == 2 else 12, bold=True)
    return h


def add_bullets(doc, items, size=12):
    for item in items:
        p = doc.add_paragraph(style="List Bullet")
        p.alignment = WD_ALIGN_PARAGRAPH.JUSTIFY
        p.paragraph_format.space_after = Pt(4)
        run = p.add_run(item)
        set_run_font(run, size=size)


def add_table(doc, headers, rows, col_widths=None):
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = "Table Grid"
    for i, h in enumerate(headers):
        cell = table.rows[0].cells[i]
        cell.text = ""
        p = cell.paragraphs[0]
        run = p.add_run(h)
        set_run_font(run, size=11, bold=True)
    for r_i, row in enumerate(rows):
        for c_i, val in enumerate(row):
            cell = table.rows[r_i + 1].cells[c_i]
            cell.text = ""
            p = cell.paragraphs[0]
            run = p.add_run(str(val))
            set_run_font(run, size=10)
    if col_widths:
        for row in table.rows:
            for i, w in enumerate(col_widths):
                row.cells[i].width = Inches(w)
    doc.add_paragraph()
    return table


def page_break(doc):
    doc.add_page_break()


# ═══════════════════════════════════════════════════════════════════════════
# REPORT
# ═══════════════════════════════════════════════════════════════════════════

def build_report():
    doc = Document()
    section = doc.sections[0]
    section.top_margin = Cm(2.54)
    section.bottom_margin = Cm(2.54)
    section.left_margin = Cm(3.0)
    section.right_margin = Cm(2.54)

    # ── Title page ──────────────────────────────────────────────────────────
    if LOGO.exists():
        try:
            p = doc.add_paragraph()
            p.alignment = WD_ALIGN_PARAGRAPH.CENTER
            run = p.add_run()
            run.add_picture(str(LOGO), width=Inches(1.4))
        except Exception:
            pass

    for line in [
        "THE UNIVERSITY OF ZAMBIA",
        "SCHOOL OF NATURAL SCIENCES",
        "DEPARTMENT OF COMPUTING AND INFORMATICS",
    ]:
        add_para(doc, line, bold=True, size=14, align="center", space_after=4)

    add_para(doc, "", space_after=12)
    add_para(doc, "FINAL YEAR PROJECT REPORT", bold=True, size=14, align="center")
    add_para(doc, "ACADEMIC YEAR 2026", bold=True, size=12, align="center", space_after=18)

    add_para(
        doc,
        "UnZA Z CHAT — An Integrated Communication and AI-Powered Study Companion for Zambian University Students",
        bold=True,
        size=14,
        align="center",
        space_after=18,
    )
    add_para(doc, "BY", bold=True, size=12, align="center", space_after=10)
    add_para(doc, f"{INNOCENT['name']}", bold=True, size=12, align="center", space_after=2)
    add_para(doc, f"Student Number: {INNOCENT['id']}", size=12, align="center", space_after=8)
    add_para(doc, f"{RUTH['name']}", bold=True, size=12, align="center", space_after=2)
    add_para(doc, f"Student Number: {RUTH['id']}", size=12, align="center", space_after=8)
    add_para(doc, f"{KEWA['name']}", bold=True, size=12, align="center", space_after=2)
    add_para(doc, f"Student Number: {KEWA['id']}", size=12, align="center", space_after=16)

    add_para(
        doc,
        "A PROJECT REPORT SUBMITTED IN PARTIAL FULFILMENT OF THE REQUIREMENTS FOR THE AWARD OF THE DEGREE OF BACHELOR OF COMPUTER SCIENCE",
        bold=True,
        size=11,
        align="center",
        space_after=16,
    )
    add_para(doc, "SUPERVISOR: Prof. J. Phiri", bold=True, size=12, align="center")
    add_para(doc, "October 2026", bold=True, size=12, align="center")

    page_break(doc)

    # ── Copyright ───────────────────────────────────────────────────────────
    add_heading(doc, "COPYRIGHT", 1)
    add_para(
        doc,
        "All rights reserved. No part of this material may be reproduced, stored in any retrieval system, "
        "or transmitted in any form by any means, except in the case of brief quotations embodied in critical "
        "reviews and certain other non-commercial uses permitted by copyright law, without prior written "
        "permission of the authors and the University of Zambia.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        f"© 2026 {INNOCENT['name']}, {RUTH['name']}, and {KEWA['name']}. All rights reserved.",
        align="justify",
    )

    page_break(doc)

    # ── Declaration (group) ─────────────────────────────────────────────────
    add_heading(doc, "DECLARATION", 1)
    add_para(
        doc,
        f"We, {INNOCENT['name']}, {RUTH['name']}, and {KEWA['name']}, do hereby declare that this report "
        "is our own original work undertaken as a group project, and that it has not been submitted to any "
        "other college, institution or university other than the University of Zambia for the award of a degree. "
        "We further declare that all sources of information used have been duly acknowledged, and that the "
        "division of work among the three members is accurately reflected in the Contributions / Division of "
        "Work section and in Appendix A.",
        align="justify",
        first_indent=True,
    )
    add_para(doc, "", space_after=6)
    for person in (INNOCENT, RUTH, KEWA):
        add_para(doc, f"Name: {person['name']}", space_after=2)
        add_para(doc, f"Student Number: {person['id']}", space_after=2)
        add_para(doc, "Signature: _______________________________", space_after=2)
        add_para(doc, "Date: ____________________________________", space_after=10)

    page_break(doc)

    # ── Approval ────────────────────────────────────────────────────────────
    add_heading(doc, "APPROVAL", 1)
    add_para(
        doc,
        f"This report, by {INNOCENT['name']}, {RUTH['name']}, and {KEWA['name']}, has been approved as "
        "partial fulfilment of the requirements for the award of the Bachelor of Computer Science degree "
        "by the University of Zambia.",
        align="justify",
        first_indent=True,
    )
    add_para(doc, "", space_after=8)
    add_para(doc, "Students", bold=True, space_after=6)
    for person in (INNOCENT, RUTH, KEWA):
        add_para(doc, f"Name: {person['name']}    Signature: _______________    Date: ___________", space_after=6)

    add_para(doc, "", space_after=8)
    add_para(doc, "Supervisor", bold=True, space_after=6)
    add_para(doc, "Name: Prof. J. Phiri", space_after=4)
    add_para(doc, "Signature: _______________________________", space_after=4)
    add_para(doc, "Date: ____________________________________", space_after=4)

    page_break(doc)

    # ── Acknowledgements ────────────────────────────────────────────────────
    add_heading(doc, "ACKNOWLEDGEMENTS", 1)
    add_para(
        doc,
        "This project would not have been possible without the guidance, critique, and encouragement of "
        "many people. We express our deepest appreciation to our supervisor, Prof. J. Phiri, for his "
        "patience in reading through our proposal and subsequent work, and for constructive criticisms and "
        "useful suggestions that kept the project focused on a realistic, student-centred solution.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "We thank the Department of Computing and Informatics, School of Natural Sciences, University of "
        "Zambia, for providing the academic framework within which this final-year project was undertaken. "
        "We are also grateful to fellow students who acted as informal beta testers of early prototype "
        "builds, sharing usability observations on messaging, past-paper access, and the AI assistant.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Finally, we thank our families and friends for their moral and practical support throughout the "
        "development and documentation of UnZA Z CHAT.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ── Dedication ──────────────────────────────────────────────────────────
    add_heading(doc, "DEDICATION", 1)
    add_para(
        doc,
        "This work is dedicated to Zambian university students who navigate fragmented communication "
        "channels and scarce academic resources daily, and to our parents and guardians for their "
        "unwavering support of our education.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ── Abstract ────────────────────────────────────────────────────────────
    add_heading(doc, "ABSTRACT", 1)
    add_para(
        doc,
        "Zambian university students commonly rely on general-purpose messaging applications for "
        "academic collaboration while past examination papers, tutoring, and study planning remain "
        "scattered across informal channels. This final-year project presents UnZA Z CHAT, a Flutter-based "
        "mobile prototype that integrates WhatsApp-like campus messaging with an AI-powered study "
        "companion tailored to university-level workflows.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "The implemented system provides phone OTP authentication via an external Node.js backend that "
        "issues Firebase custom tokens; real-time one-to-one and group chat with AES-encrypted message "
        "bodies stored in Cloud Firestore; communities, status, broadcasts, and ZegoCloud voice/video "
        "calls; a course-linked past-paper repository on Firebase Storage; a study planner with local "
        "notifications; virtual classroom session screens; lecturer-oriented routes; threaded campus "
        "discussions (ZFeed/Threads); and an AI module that proxies Anthropic Claude through the backend "
        "for tutoring, quizzes, summaries, and study insights. Design decisions that diverge from the "
        "original proposal—Firestore rather than Realtime Database for chat documents, phone OTP rather "
        "than email/JWT, and Claude rather than GPT-3.5—are documented as intentional engineering choices.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Development followed an iterative agile approach. Functional modules were exercised through "
        "manual and informal peer testing on development builds; a formal survey of twenty students with "
        "statistical analysis was planned in the proposal but is reported here only as planned/partial "
        "evaluation, without fabricated quantitative results. The prototype demonstrates a viable "
        "architecture for unifying campus communication and study support, while highlighting limitations "
        "around LMS integration, model fine-tuning, and production hardening.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Keywords: Mobile learning; Flutter; Firebase; Cloud Firestore; AI tutoring; campus messaging; "
        "past examination papers; Technology Acceptance Model; University of Zambia.",
        align="justify",
    )

    page_break(doc)

    # ── TOC placeholder ─────────────────────────────────────────────────────
    add_heading(doc, "TABLE OF CONTENTS", 1)
    add_para(
        doc,
        "[Update fields in Microsoft Word: References → Table of Contents, or right-click → Update Field.]",
        size=11,
    )
    toc_items = [
        "Copyright",
        "Declaration",
        "Approval",
        "Acknowledgements",
        "Dedication",
        "Abstract",
        "List of Tables",
        "List of Figures",
        "List of Abbreviations",
        "CHAPTER 1: Introduction and Background .............................................. 1",
        "CHAPTER 2: Literature Review .................................................................. 1",
        "CHAPTER 3: Methodology ........................................................................ 1",
        "CHAPTER 4: Results — System Implementation ..................................... 1",
        "CHAPTER 5: Discussion and Conclusions ............................................... 1",
        "References",
        "Appendix A: Division of Work",
        "Appendix B: Screenshot Placeholders / User Guide Notes",
    ]
    for t in toc_items:
        add_para(doc, t, size=11, space_after=2)

    page_break(doc)

    add_heading(doc, "LIST OF TABLES", 1)
    tables_list = [
        "Table 1.1: Project objectives mapped to implemented modules",
        "Table 2.1: Summary of related works and gaps",
        "Table 3.1: Functional requirements",
        "Table 3.2: Non-functional requirements",
        "Table 3.3: Software requirements",
        "Table 3.4: Hardware requirements",
        "Table 3.5: Major Firestore collections",
        "Table 4.1: Implemented feature modules and primary services",
        "Table A.1: Division of work among group members",
    ]
    for t in tables_list:
        add_para(doc, t, size=11, space_after=2)

    page_break(doc)

    add_heading(doc, "LIST OF FIGURES", 1)
    figs = [
        "Figure 3.1: High-level system architecture (client–backend–Firebase–AI)",
        "Figure 3.2: Student authentication and profile-setup use cases (textual)",
        "Figure 3.3: Messaging send/receive sequence (textual)",
        "Figure 4.1: Splash / Login / OTP screens [PLACEHOLDER — insert screenshot]",
        "Figure 4.2: Home and chat list [PLACEHOLDER — insert screenshot]",
        "Figure 4.3: Chat conversation with media [PLACEHOLDER — insert screenshot]",
        "Figure 4.4: Courses and past papers [PLACEHOLDER — insert screenshot]",
        "Figure 4.5: AI assistant home and chat [PLACEHOLDER — insert screenshot]",
        "Figure 4.6: Planner and classroom [PLACEHOLDER — insert screenshot]",
        "Figure 4.7: Threads / ZFeed [PLACEHOLDER — insert screenshot]",
        "Figure 4.8: Lecturer home [PLACEHOLDER — insert screenshot]",
    ]
    for f in figs:
        add_para(doc, f, size=11, space_after=2)

    page_break(doc)

    add_heading(doc, "LIST OF ABBREVIATIONS", 1)
    abbrevs = [
        ("AES", "Advanced Encryption Standard"),
        ("AI", "Artificial Intelligence"),
        ("API", "Application Programming Interface"),
        ("FCM", "Firebase Cloud Messaging"),
        ("JWT", "JSON Web Token"),
        ("LMS", "Learning Management System"),
        ("OTP", "One-Time Password"),
        ("PDF", "Portable Document Format"),
        ("PEU", "Perceived Ease of Use"),
        ("PU", "Perceived Usefulness"),
        ("REST", "Representational State Transfer"),
        ("SDK", "Software Development Kit"),
        ("SSE", "Server-Sent Events"),
        ("TAM", "Technology Acceptance Model"),
        ("UI", "User Interface"),
        ("UNZA", "University of Zambia"),
        ("UTAUT", "Unified Theory of Acceptance and Use of Technology"),
    ]
    for ab, meaning in abbrevs:
        add_para(doc, f"{ab} — {meaning}", size=11, space_after=2)

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # CHAPTER 1
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "CHAPTER 1: INTRODUCTION AND BACKGROUND", 1)
    add_heading(doc, "1.1 Introduction", 2)
    add_para(
        doc,
        "This chapter introduces the UnZA Z CHAT project. It provides background on the fragmented "
        "digital environment facing Zambian university students, states the problem addressed by the "
        "system, presents the aim and objectives, outlines scope and significance, and describes how "
        "the remainder of the report is organised. The chapter updates the approved proposal to reflect "
        "what was actually designed and implemented in the Flutter codebase during Academic Year 2026.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.2 Background of the Study", 2)
    add_para(
        doc,
        "University students in Zambia face two interconnected challenges: they lack a dedicated, "
        "organised platform for academic resources, and they rely heavily on general messaging apps "
        "such as WhatsApp for collaboration. While WhatsApp is convenient, it is not designed for "
        "academic purposes—conversations are unstructured, past papers get lost in chat history, and "
        "there is no integrated support for studying. Existing study platforms such as ELICATE and "
        "PastPapers ZM focus primarily on secondary school, leaving university students without a "
        "centralised repository for past papers or context-aware AI tutoring.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Mobile applications have become the preferred solution for many organisational information "
        "needs because they provide convenient ways to collect, store, process and present information "
        "when needed [1]. Android continues to hold a substantial share of the mobile market in Zambia "
        "[2], making a cross-platform Flutter client that prioritises Android deployment a pragmatic "
        "choice while retaining a path to other targets. Research on technology adoption in higher "
        "education shows that students are more likely to use a system when it integrates into daily "
        "routines [4]. Messaging apps are already part of students’ lives, making them a natural entry "
        "point for academic tools. Studies on mobile learning in developing contexts emphasise low-data "
        "usage, offline access to downloaded materials, and local relevance [5].",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "UnZA Z CHAT therefore merges a campus messaging experience with study tools: private and "
        "group chat, communities, status, calls, past papers, an AI study companion, threaded forums "
        "(ZFeed), a study planner, and classroom-oriented screens for students and lecturers. The "
        "Technology Acceptance Model (TAM) [4] informs design choices around perceived usefulness "
        "and ease of use.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.3 Statement of the Problem", 2)
    add_para(
        doc,
        "Zambian university students currently manage academic life using a fragmented set of tools:",
        align="justify",
        first_indent=True,
    )
    add_bullets(
        doc,
        [
            "Communication is scattered across WhatsApp, Telegram, and SMS, making it difficult to retrieve important information shared weeks earlier.",
            "Academic resources such as past papers are obtained through informal channels—WhatsApp groups, photocopies, or library archives—with no centralised, searchable repository.",
            "Tutoring is either expensive (private tutors) or generic (consumer chatbots), often lacking context specific to local courses.",
            "Study planning is done manually, with limited personalised reminders or progress tracking inside the same app used for collaboration.",
        ],
    )
    add_para(
        doc,
        "Existing digital solutions either ignore the university sector or fail to combine communication "
        "and academic support in one place. Fragmentation leads to wasted time, increased costs, and "
        "reduced academic performance. This project addresses the gap by delivering a unified prototype "
        "that integrates real-time messaging with study tools for Zambian university students.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.4 Aim of the Study", 2)
    add_para(
        doc,
        "The aim of this project is to design and develop a mobile application prototype, named "
        "UnZA Z CHAT, that integrates a WhatsApp-like messaging system with an AI-powered study "
        "companion, providing Zambian university students with a centralised platform for communication, "
        "access to past papers, intelligent tutoring, forums, classroom support, and study planning.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.5 Project Objectives", 2)
    add_para(doc, "The project pursued the following objectives:", align="justify")
    objectives = [
        "To analyse core features of messaging apps and study platforms in order to identify functionalities suitable for an integrated campus application.",
        "To design a system architecture supporting real-time messaging, past-paper storage, AI Q&A, discussion threads, planner reminders, and classroom sessions within one application.",
        "To implement a functional Flutter prototype including authentication, private/group messaging, communities/status/calls, searchable past papers with download/open, AI-assisted study tools, ZFeed/Threads, planner notifications, and lecturer-oriented routes.",
        "To evaluate the prototype through iterative development testing and informal peer feedback on usability and perceived usefulness (formal large-N statistical evaluation remains recommended future work).",
        "To document the development process, technical decisions, and contribution of each group member for academic submission and defence.",
    ]
    for i, obj in enumerate(objectives, 1):
        add_para(doc, f"{i}. {obj}", align="justify", space_after=6)

    add_para(doc, "Table 1.1: Project objectives mapped to implemented modules", bold=True, size=11)
    add_table(
        doc,
        ["Objective", "Primary modules in codebase"],
        [
            ["1 Analysis", "Feature comparison informed Chat, Papers, AI, Threads, Planner screens"],
            ["2 Architecture", "Flutter client + Node backend + Firebase + Zego + Claude API"],
            ["3 Implementation", "lib/screens/*, lib/services/*, router, Firebase configs"],
            ["4 Evaluation", "Manual QA, widget/unit tests (helpers, voice intents), peer demos"],
            ["5 Documentation", "This report, defence slides, README / config notes"],
        ],
    )

    add_heading(doc, "1.6 Importance / Significance of the Study", 2)
    add_para(
        doc,
        "The study is significant because it demonstrates a practical, locally relevant integration of "
        "communication and learning support for university students. For students, a single app reduces "
        "context-switching between chat groups and study resources. For lecturers, dedicated routes "
        "support course and classroom workflows. For the Department, the project contributes a "
        "reproducible software artefact and an honest account of modern mobile/cloud/AI integration "
        "choices. Theoretically, the work applies TAM-oriented design thinking to a campus messaging "
        "and study companion in the Zambian higher-education context.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.7 Scope of the Study", 2)
    add_para(doc, "In scope:", bold=True)
    add_bullets(
        doc,
        [
            "Cross-platform Flutter/Dart client with Android as the primary deployment target; web/desktop builds are possible for development.",
            "Node.js backend endpoints for OTP authentication, AI proxying, and notification helpers; Firebase Auth, Cloud Firestore, Storage, and Messaging for core data and push.",
            "Messaging (direct/group), encryption of message bodies, communities, status, broadcasts, and Zego-backed calls when credentials are configured.",
            "Courses, past papers (PDF upload/metadata), exam simulator screens, planner with local notifications, classroom/live session UI, lecturer mode routes.",
            "AI study tools (chat, quiz, summary, group summarizer, insights) via Claude through the backend; ZFeed/Threads forums.",
            "Technical documentation and group contribution reporting.",
        ],
    )
    add_para(doc, "Out of scope / future work:", bold=True)
    add_bullets(
        doc,
        [
            "Full public app-store release and university-wide production operations.",
            "Deep integration with official university LMS systems.",
            "Fine-tuning a custom large language model on local curricula.",
            "Subscription billing or mobile-money premium features (mentioned as future options in the proposal).",
            "Fabricated large-scale survey statistics; formal SPSS analysis was not completed as a reported result in this submission.",
        ],
    )

    add_heading(doc, "1.8 Organization of the Report", 2)
    add_para(
        doc,
        "Chapter 1 introduces the problem and aims. Chapter 2 reviews literature on mobile learning, "
        "messaging, AI tutoring, and technology adoption. Chapter 3 presents methodology, requirements, "
        "architecture, and design. Chapter 4 reports implementation results mapped to real modules and "
        "screens. Chapter 5 discusses outcomes against objectives, limitations, recommendations, and "
        "future work. References and appendices follow, including the division of work among the three "
        "group members.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "1.9 Chapter Summary", 2)
    add_para(
        doc,
        "This chapter established the background, problem, aim, objectives, significance, and scope of "
        "UnZA Z CHAT as an integrated campus communication and AI study companion. The following "
        "chapter reviews related literature and identifies the gaps this prototype addresses.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # CHAPTER 2
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "CHAPTER 2: LITERATURE REVIEW", 1)
    add_heading(doc, "2.1 Introduction", 2)
    add_para(
        doc,
        "This chapter reviews literature relevant to integrated campus messaging and AI-supported "
        "study tools. It covers technology adoption in education, theoretical models (especially TAM), "
        "messaging and collaboration tools, digital repositories for examination materials, AI tutoring, "
        "and related systems. The chapter closes with a gap analysis that motivates UnZA Z CHAT.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.2 Technology Adoption in Education", 2)
    add_para(
        doc,
        "Educational institutions increasingly adopt digital platforms, yet pace and depth vary by "
        "context. In Zambia, university students have widely embraced mobile messaging but still lack "
        "dedicated academic platforms that unify resources and communication. Literature on study "
        "companions commonly groups capabilities into access to past papers, intelligent tutoring, peer "
        "communication, and progress monitoring [3]. E-services in the form of educational apps are "
        "essential to modern learning; however, many students in developing countries still rely on "
        "informal channels, and adoption of integrated digital tools remains uneven [7].",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.3 Theories and Models for Adoption of Technologies", 2)
    add_para(
        doc,
        "The Technology Acceptance Model (TAM) remains among the most widely used models explaining "
        "user acceptance of information systems [4]. Originating from Davis’s work and rooted in the "
        "Theory of Reasoned Action, TAM emphasises Perceived Usefulness (PU)—belief that a system "
        "improves performance—and Perceived Ease of Use (PEU)—belief that use requires little effort. "
        "Design implications for UnZA Z CHAT include familiar chat metaphors (supporting PEU) and "
        "tangible academic payoffs such as past papers and AI help (supporting PU).",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Sakala and Phiri [8] applied TAM to mobile banking adoption in Zambia and found strong "
        "relationships involving PU, PEU, attitude, and intention. Soneka and Phiri [9] reported similar "
        "patterns for e-tax systems in rural Zambia. Daka and Phiri [10] used UTAUT for e-banking and "
        "highlighted performance expectancy and effort expectancy. Although these studies are not "
        "education-app studies, they reinforce that Zambian users respond to clear usefulness and "
        "simplified interfaces—guidance transferred into our UI and feature prioritisation.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Research on educational software also notes reluctance when systems are difficult to use; "
        "involving stakeholders during development improves PEU [10]. Our iterative builds and informal "
        "peer feedback sessions were intended to surface such friction early.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.4 Messaging Platforms and Academic Collaboration", 2)
    add_para(
        doc,
        "Instant messaging platforms dominate student coordination. Their strengths—low friction, "
        "media sharing, group formation—also create academic weaknesses: poor search for learning "
        "artefacts, no structured course forums, and no first-class past-paper library. Systems analysis "
        "and design literature emphasises aligning software processes with user tasks [1], [11]. UnZA Z "
        "CHAT intentionally reuses familiar chat patterns while adding academic structure (courses, "
        "papers, planner, threads) so that usefulness does not require abandoning everyday communication "
        "habits.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.5 Digital Past-Paper Repositories and Offline Study", 2)
    add_para(
        doc,
        "Secondary-focused platforms demonstrate demand for examination archives [3], but university "
        "coverage remains limited. A university-oriented repository should support upload, metadata "
        "(course, year, semester), verification by trusted roles, and download/open for offline reading. "
        "Connectivity constraints in developing contexts further motivate caching and open-in-external-PDF "
        "workflows rather than always-online viewers only [5].",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.6 AI-Powered Tutoring and Generative Models", 2)
    add_para(
        doc,
        "Generative AI can answer questions, summarise materials, and generate practice items. Consumer "
        "tools lack campus identity, course context, and integration with peer communication. For this "
        "prototype, the proposal initially referenced OpenAI GPT-3.5; implementation routes AI requests "
        "through a Node backend to Anthropic Claude, keeping API keys server-side and authenticating "
        "clients with Firebase ID tokens. This separation improves key hygiene and allows prompt/tooling "
        "evolution without shipping secrets in the mobile binary.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.7 Related Works and Gaps", 2)
    add_para(doc, "Table 2.1: Summary of related works and gaps", bold=True, size=11)
    add_table(
        doc,
        ["Work / domain", "Contribution", "Gap relative to this project"],
        [
            ["WhatsApp / Telegram", "Ubiquitous chat & groups", "Not academic; weak resource library"],
            ["ELICATE / PastPapers ZM", "Secondary e-learning & papers", "Limited university integration"],
            ["Consumer ChatGPT apps", "General tutoring", "No campus auth, courses, or chat mesh"],
            ["Sakala & Phiri (TAM banking)", "PU/PEU drive adoption in ZM", "Domain ≠ education apps"],
            ["Soneka & Phiri (e-tax TAM)", "Simplify + usefulness", "Domain ≠ campus study tools"],
            ["Daka & Phiri (UTAUT e-banking)", "Performance/effort expectancy", "Not messaging+study combo"],
            ["LMS platforms (generic)", "Course content & grades", "Weak social chat; slow mobile UX"],
            ["Church/IS case studies [12]–[17]", "Local IS for communities", "Different domain; lessons on local fit"],
            ["Sommerville SE [11]", "Process & quality guidance", "Not a product; informs methodology"],
            ["Mobile money / ride-hail localisations [5],[6]", "Adapt global models locally", "Analogy for localising chat+study"],
        ],
    )
    add_para(
        doc,
        "The synthesised gap is clear: no widely adopted Zambian university mobile platform currently "
        "combines encrypted campus messaging, communities/calls, verified past papers, planner, "
        "classroom hooks, forums, and backend-mediated AI tutoring in one coherent product. UnZA Z CHAT "
        "targets that intersection as a prototype.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.8 Mobile Learning in Developing Contexts", 2)
    add_para(
        doc,
        "Mobile learning research in developing contexts repeatedly emphasises intermittent connectivity, "
        "device sharing, and cost of data as constraints on always-online designs [5]. For UnZA Z CHAT, "
        "these constraints informed decisions such as opening past papers in the device PDF viewer after "
        "download, caching author display data with short TTLs in Threads, and keeping AI calls optional "
        "rather than blocking core chat when the backend is unreachable. Familiar chat metaphors reduce "
        "training overhead—an important PEU consideration when onboarding large first-year cohorts.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Localisation is not only language translation; it includes institutional structure (schools, "
        "programmes, student versus lecturer roles) and social norms around group communication. The "
        "application therefore encodes UNZA-oriented programme/course data and separates lecturer "
        "navigation from the student home experience, rather than presenting a generic global LMS clone.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.9 Software Engineering and Information Systems Perspectives", 2)
    add_para(
        doc,
        "From a software engineering standpoint, Sommerville stresses iterative delivery, configuration "
        "management, and security as first-class concerns [11]. Whitten et al. emphasise modelling "
        "processes that mirror stakeholder tasks [1]. Applied here, student tasks (chat a classmate, "
        "find a paper, ask a course question, plan revision) became primary epics. Security was treated "
        "as cross-cutting: authentication before data access, encryption for message bodies, and "
        "server-side custody of AI credentials.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Information systems case studies outside education—such as community and church management "
        "systems [12]–[17]—still offer transferable lessons: stakeholder involvement, local process fit, "
        "and the risk of over-building unused modules. Those lessons cautioned the team against "
        "premature premium billing features while still allowing academically valuable expansions "
        "(classroom, calls, ZFeed) that students actively requested during informal demos.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.10 Synthesis for Design", 2)
    add_para(
        doc,
        "Synthesising the review: (i) adoption depends on usefulness and ease; (ii) chat is the daily "
        "habit to build upon; (iii) university past-paper and tutoring gaps are real; (iv) AI must be "
        "integrated with identity and course context; (v) engineering quality and honest evaluation "
        "matter for academic credibility. UnZA Z CHAT’s feature map and architecture follow directly "
        "from this synthesis.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "2.11 Chapter Summary", 2)
    add_para(
        doc,
        "Literature on mobile adoption, TAM/UTAUT evidence from Zambia, messaging habits, past-paper "
        "platforms, generative AI, and software/IS engineering collectively justify an integrated campus "
        "application. Related works leave a gap that this project addresses through a "
        "Flutter–Firebase–Node–Claude architecture. Chapter 3 details the methodology and design used "
        "to build the prototype.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # CHAPTER 3
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "CHAPTER 3: METHODOLOGY", 1)
    add_heading(doc, "3.1 Introduction", 2)
    add_para(
        doc,
        "This chapter describes the research and engineering methodology used to design and implement "
        "UnZA Z CHAT. It covers research design, iterative development, requirements, architecture, "
        "logical design artefacts (described textually), database collections, security design, "
        "implementation approach, and testing/deployment strategy. Computer-science project emphasis is "
        "placed on system design and implementation rather than large-scale survey statistics.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.2 Research Design", 2)
    add_para(
        doc,
        "The project adopted an applied, design-and-build research approach with iterative (agile) "
        "increments. Each iteration delivered a vertical slice: authentication, messaging, past papers, "
        "AI, forums/planner, classroom/calls, then polish and documentation. This matches Sommerville’s "
        "guidance that evolutionary delivery reduces risk when requirements emerge through use [11]. "
        "TAM concepts guided usability priorities but were not used to run a formal structural-equation "
        "model in this submission.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.3 Baseline / Evaluation Approach", 2)
    add_para(
        doc,
        "The approved proposal planned testing with at least twenty university students and structured "
        "feedback on usability, performance, and perceived usefulness. In practice, evaluation to date "
        "has been formative: developer testing on Android emulator/device and Chrome, automated unit/"
        "widget tests for helpers and voice intents, and informal peer walkthroughs of prototype builds. "
        "No fabricated SPSS outputs, response rates, or percentage adoption figures are reported. A "
        "formal questionnaire-based TAM evaluation remains recommended future work.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.4 System Design and Implementation Overview", 2)
    add_heading(doc, "3.4.1 Proposed Business Process", 3)
    add_para(
        doc,
        "A student installs the app, verifies a phone number via OTP, completes a profile (role: student "
        "or lecturer), then accesses home navigation for chats, status, calls, courses/papers, AI, "
        "planner, threads, and profile. Lecturers follow lecturer-specific home routes for courses, "
        "classroom, AI, and planner. Messaging and presence update Firestore in real time; AI and OTP "
        "call the Node backend; media and papers use Firebase Storage; calls use Zego when configured.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.4.2 Functional Requirements", 3)
    add_para(doc, "Table 3.1: Functional requirements", bold=True, size=11)
    add_table(
        doc,
        ["ID", "Requirement", "Priority"],
        [
            ["FR-01", "Phone OTP login and Firebase session", "High"],
            ["FR-02", "Profile setup with student/lecturer role", "High"],
            ["FR-03", "Direct and group encrypted messaging", "High"],
            ["FR-04", "Communities, status, broadcasts", "Medium"],
            ["FR-05", "Voice/video calls via Zego", "Medium"],
            ["FR-06", "Course browse/enrol and past-paper CRUD/open", "High"],
            ["FR-07", "Study planner with local reminders", "High"],
            ["FR-08", "AI chat, quiz, summary, insights", "High"],
            ["FR-09", "Threads/ZFeed posts and engagement", "High"],
            ["FR-10", "Classroom session list and live room entry", "Medium"],
            ["FR-11", "Lecturer navigation stream", "Medium"],
            ["FR-12", "Push notification hooks (FCM)", "Medium"],
        ],
    )

    add_heading(doc, "3.4.3 Non-Functional Requirements", 3)
    add_para(doc, "Table 3.2: Non-functional requirements", bold=True, size=11)
    add_table(
        doc,
        ["ID", "Requirement", "Notes"],
        [
            ["NFR-01", "Security", "OTP + Firebase Auth; AES chat bodies; fail-closed encrypt"],
            ["NFR-02", "Performance", "Firestore streams; AI timeouts (~60s); SSE streaming where available"],
            ["NFR-03", "Usability", "Familiar chat UI; role-based home"],
            ["NFR-04", "Configurability", "BACKEND_URL, ZEGO_*, TENOR_KEY via dart-define"],
            ["NFR-05", "Maintainability", "Service-layer separation under lib/services"],
            ["NFR-06", "Portability", "Flutter; Android primary"],
        ],
    )

    add_heading(doc, "3.4.4 Hardware and Software Requirements", 3)
    add_para(doc, "Table 3.3: Software requirements", bold=True, size=11)
    add_table(
        doc,
        ["Component", "Technology"],
        [
            ["Mobile client", "Flutter/Dart 3.x, Provider, go_router"],
            ["Backend API", "Node.js (OTP, AI proxy, notifications)"],
            ["Auth / DB / Storage", "Firebase Auth, Cloud Firestore, Storage, FCM"],
            ["Realtime media calls", "ZegoCloud UIKit prebuilt call"],
            ["AI model provider", "Anthropic Claude (via backend)"],
            ["CI / builds", "Codemagic YAML present in repo"],
            ["Local tools", "Android Studio / Flutter SDK, VS Code/Cursor"],
        ],
    )
    add_para(doc, "Table 3.4: Hardware requirements", bold=True, size=11)
    add_table(
        doc,
        ["Role", "Minimum"],
        [
            ["Developer workstation", "Windows/macOS/Linux, 8GB+ RAM, Internet"],
            ["Test device", "Android phone or emulator; optional Chrome for web"],
            ["End user (target)", "Smartphone with camera/mic for calls; storage for PDFs"],
        ],
    )

    add_heading(doc, "3.5 Design Decisions Relative to the Proposal", 2)
    add_para(
        doc,
        "Several stack choices evolved during implementation. These are recorded as design decisions, "
        "not accidental drift:",
        align="justify",
        first_indent=True,
    )
    add_bullets(
        doc,
        [
            "Data store for chat: Cloud Firestore document/collection model with realtime snapshots was used instead of Firebase Realtime Database, favouring structured queries (e.g., papers by course/year) and security-rule patterns already used across courses, threads, and planner subcollections.",
            "Authentication: Phone OTP through the Node backend issuing Firebase custom tokens replaced email/password + application-level JWT, aligning with mobile-first campus usage and Firebase security rules keyed on uid.",
            "AI provider: Claude via a backend proxy replaced direct GPT-3.5 client calls, improving secret management and enabling server-side tooling/prompts.",
            "Scope growth: Communities, status, Zego calls, lecturer mode, classroom live sessions, voice assistant, and ZFeed features expanded the proposal’s core set while remaining consistent with the aim of an integrated campus companion.",
        ],
    )

    add_heading(doc, "3.6 System High-Level Architecture", 2)
    add_para(
        doc,
        "Figure 3.1 (textual architecture). The Flutter client presents UI screens routed by go_router. "
        "Domain logic lives in service classes (ChatService, AuthService, AiService, PapersService, "
        "PlannerService, ThreadsService, CallService, etc.). The client talks to: (a) Firebase SDKs for "
        "Auth state, Firestore reads/writes/listeners, Storage uploads, and FCM; (b) the Node backend "
        "over HTTPS for /api/auth OTP flows and /api/ai endpoints, attaching Firebase ID tokens; "
        "(c) Zego SDKs for call media when ZEGO_APP_ID and ZEGO_APP_SIGN are supplied. Claude API keys "
        "remain on the server. This three-tier-plus-BaaS arrangement separates concerns and matches "
        "common production mobile architectures.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.7 Logical Design (Use Cases, Sequence, Classes)", 2)
    add_para(
        doc,
        "Primary student use cases include: Register/Login with OTP; Complete Profile; Start Direct Chat; "
        "Create Group; Send Encrypted Message; Post Status; Join Community; Place/Receive Call; Browse "
        "Courses; Upload/Open Past Paper; Ask AI; Take Quiz; Manage Planner Events; Create Thread Post; "
        "Join Classroom Session. Lecturer use cases add course/classroom management surfaces under "
        "/lecturer/* routes.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Message send sequence (Figure 3.3 textual): User composes message → ChatService obtains/creates "
        "chat document → EncryptionService encrypts plaintext with per-chat AES key → ciphertext written "
        "to Firestore messages subcollection → listeners on peer devices decrypt and render → optional "
        "FCM notification via backend helper. Encrypt failures fail closed so plaintext is not stored.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Key client-side class/service responsibilities: AuthService (OTP + profile), ChatService "
        "(chats/messages/media), EncryptionService (AES), CommunitiesService, StatusService, "
        "PresenceService, CallService/ZegoService, CoursesService, PapersService, PlannerService, "
        "ThreadsService, AiService, FcmService, VoiceAssistantService, plus UI screens under lib/screens.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.8 Database Design", 2)
    add_para(doc, "Table 3.5: Major Firestore collections (simplified)", bold=True, size=11)
    add_table(
        doc,
        ["Collection / path", "Purpose"],
        [
            ["users/{uid}", "Profile, role, phone, FCM tokens, settings"],
            ["users/{uid}/timetable|studyPlans|studyGuides", "Planner data"],
            ["chats/{chatId}", "Direct/group metadata, last message"],
            ["chats/{chatId}/messages", "Encrypted message payloads"],
            ["communities, status, broadcasts, calls", "Social / call metadata"],
            ["courses, papers", "Academic catalogue and PDF metadata"],
            ["threads (+ comments)", "ZFeed forum posts"],
            ["classroom / session docs", "Scheduled/live class metadata"],
        ],
    )
    add_para(
        doc,
        "Binary artefacts (avatars, chat media, paper PDFs) are stored in Firebase Storage with "
        "download URLs referenced from Firestore documents.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.9 Security Design", 2)
    add_para(
        doc,
        "Security controls include: phone OTP verification before custom-token sign-in; Firebase ID "
        "tokens for backend AI/auth-adjacent calls; AES-256-CBC per-chat encryption of message bodies "
        "with fail-closed behaviour; role fields distinguishing student and lecturer experiences; "
        "optional local biometric/chat-lock helpers; dart-define injection of Zego/Tenor secrets so they "
        "are not hard-coded; lecturer paper verification intended to be enforced with Firestore rules. "
        "Production hardening (rule audits, abuse rate limits, content moderation at scale) is noted as "
        "ongoing work.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.10 System Implementation Approach", 2)
    add_para(
        doc,
        "Implementation used Flutter with Provider for state where needed and go_router for declarative "
        "navigation (see lib/router.dart). Feature work was split across the three members by module "
        "(Appendix A). The backend URL defaults to http://localhost:5000 and is overridden per device "
        "target. Codemagic configuration supports CI builds. README documents emulator, device, and "
        "Chrome run commands.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.11 System Testing and Deployment", 2)
    add_para(
        doc,
        "Testing combined: (i) flutter analyze / widget tests (e.g., helpers_test, voice_intents_test); "
        "(ii) manual exploratory testing of auth, chat, papers, AI, and navigation; (iii) informal peer "
        "demos. Deployment for demonstration uses debug/profile APKs or flutter run with dart-defines; "
        "store release was out of scope. Zego-dependent call features are disabled gracefully when "
        "credentials are absent.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.12 Iteration Plan (as Executed)", 2)
    add_para(
        doc,
        "Development broadly followed the proposal schedule with parallelisation across the three "
        "members after shared scaffolding (Flutter project, Firebase options, router shell):",
        align="justify",
        first_indent=True,
    )
    add_bullets(
        doc,
        [
            "Iteration 0 — Repository setup, theming, navigation shell, configuration via dart-define.",
            "Iteration 1 — OTP authentication, profile setup, role-based home routing.",
            "Iteration 2 — Direct/group chat, encryption, media messages, presence.",
            "Iteration 3 — Courses and past-paper repository with Storage uploads.",
            "Iteration 4 — AI endpoints integration (chat/stream, quiz, summary, insights).",
            "Iteration 5 — Threads/ZFeed, planner notifications, communities/status.",
            "Iteration 6 — Calls (Zego), classroom/live sessions, lecturer stream, broadcasts.",
            "Iteration 7 — Hardening, informal peer demos, documentation and defence materials.",
        ],
    )

    add_heading(doc, "3.13 Tools, Collaboration, and Quality Practices", 2)
    add_para(
        doc,
        "The team used Git for version control, Flutter’s analyzer and selected unit/widget tests for "
        "regression on pure logic, and shared Firebase/backend environments for integration checks. "
        "Module ownership reduced merge conflicts: messaging services versus academic services versus "
        "AI/auth/threads. Integration points (router paths, shared user profile fields, notification "
        "payloads) were coordinated by the group coordinator. README run instructions document "
        "emulator, LAN device, and Chrome backend URL patterns.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.14 Ethical and Data Considerations", 2)
    add_para(
        doc,
        "The prototype stores phone numbers, display names, chat ciphertext, academic uploads, and "
        "optional AI conversation content. For academic demonstration, test accounts and simulated "
        "course data were preferred. Any broader student trial should obtain informed consent, minimise "
        "collected data, and follow departmental guidance. AI prompts should avoid submitting "
        "sensitive personal data. These considerations are stated here to frame responsible next steps "
        "rather than to claim a completed institutional ethics review for a large survey.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "3.15 Chapter Summary", 2)
    add_para(
        doc,
        "The methodology combined agile delivery with explicit requirements, a Firebase-centred data "
        "plane, a Node AI/OTP edge, documented deviations from the proposal, an executed iteration "
        "plan, and ethical cautions for future trials. Chapter 4 presents implementation results "
        "module by module.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # CHAPTER 4
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "CHAPTER 4: RESULTS — SYSTEM IMPLEMENTATION", 1)
    add_heading(doc, "4.1 Introduction", 2)
    add_para(
        doc,
        "This chapter presents the implemented UnZA Z CHAT prototype. Results are organised by major "
        "feature modules corresponding to the group’s division of work. Screenshot figures are listed as "
        "placeholders for images to be pasted from a running build before final binding/printing.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "4.2 Implemented Module Map", 2)
    add_para(doc, "Table 4.1: Implemented feature modules and primary services", bold=True, size=11)
    add_table(
        doc,
        ["Module", "Lead member", "Key code areas"],
        [
            ["Messaging, communities, status, calls, broadcasts", INNOCENT["name"], "chat_*, communities_*, status_*, calls_*, broadcast_*, encryption_*"],
            ["Courses, papers, planner, classroom, lecturer academics", RUTH["name"], "courses_*, papers_*, planner_*, classroom_*, lecturer_*"],
            ["Auth/backend, AI, threads/ZFeed, voice, FCM, deploy", KEWA["name"], "auth_*, ai_*, threads_*, voice_*, fcm_*, config, codemagic"],
        ],
    )

    add_heading(doc, "4.3 Authentication and Roles", 2)
    add_para(
        doc,
        "Splash routing leads to login. The user enters a phone number; AuthService.sendOtp calls the "
        "backend; OtpScreen collects the code; AuthService.verifyOtp exchanges it for a Firebase custom "
        "token and persists phoneNumber on users/{uid}. New users complete ProfileSetupScreen (full name, "
        "role, university/program fields). Students land on /home; lecturers on /lecturer/home. "
        "[Figure 4.1 PLACEHOLDER: Splash / Login / OTP / Profile setup screenshots]",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, f"4.4 Messaging and Real-time Communication (Lead: {INNOCENT['name']})", 2)
    add_para(
        doc,
        "ChatListScreen and ChatScreen implement WhatsApp-like conversations. ChatService creates "
        "deterministic direct chat IDs, supports groups, starred messages, and media uploads to Storage. "
        "EncryptionService applies AES-256-CBC per chat; failures prevent sending plaintext. "
        "CommunitiesService powers campus communities; StatusService handles ephemeral status; "
        "BroadcastService supports broadcast messaging; PresenceService tracks online indicators. "
        "CallService with ZegoService enables voice/video when dart-defines are set; otherwise the app "
        "logs that calls are disabled. [Figures 4.2–4.3 PLACEHOLDER]",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, f"4.5 Academic Resources and Classroom (Lead: {RUTH['name']})", 2)
    add_para(
        doc,
        "CourseListScreen and CourseCatalogScreen, backed by CoursesService and unza_programs data, "
        "expose programme/course browsing. PapersService streams papers by course, supports PDF upload "
        "to Storage, metadata in Firestore, lecturer verification hooks, and open-via-url_launcher. "
        "ExamSimulatorScreen and adaptive learning path routes provide practice-oriented UI. "
        "PlannerService stores timetable/studyPlans/studyGuides under the user document and schedules "
        "local notifications. ClassroomScreen lists sessions; LiveSessionScreen joins a roomId for live "
        "activity. Lecturer screens mirror academic operations in a separate navigation stream. "
        "[Figures 4.4, 4.6, 4.8 PLACEHOLDER]",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, f"4.6 AI Companion, Forums, and Platform Integration (Lead: {KEWA['name']})", 2)
    add_para(
        doc,
        "AiHomeScreen offers entry points to AI chat, course quizzes, summaries, group summarizer, and "
        "study insights. AiService posts conversation history to /api/ai/chat (and streaming variants), "
        "authenticated with Firebase ID tokens; responses are rendered with markdown helpers. "
        "VoiceAssistantService and voice intents enable hands-free prompts. ThreadsScreen and related "
        "ZFeed routes implement campus forum posts, detail views, search, bookmarks, and author "
        "notifications. FcmService registers tokens and handles foreground/open events. AppConfig "
        "centralises BACKEND_URL and optional third-party keys. [Figures 4.5, 4.7 PLACEHOLDER]",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "4.7 Cross-Cutting Platform Behaviours", 2)
    add_para(
        doc,
        "Several behaviours cut across modules and are visible in results: (i) go_router centralises "
        "deep links such as /chats/:chatId, /courses/:courseId/papers, /ai/quiz/:courseId, and "
        "/threads/:postId; (ii) Provider/ChangeNotifier patterns support voice assistant overlay state; "
        "(iii) connectivity-aware UX and fail-closed encryption protect messaging integrity; "
        "(iv) markdown rendering improves AI answer readability; (v) local notifications surface planner "
        "reminders even when the app is backgrounded (platform permitting).",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "4.8 System Validation", 2)
    add_para(
        doc,
        "Validation focused on demonstrating that each high-priority functional requirement is reachable "
        "in a development build with Firebase and backend configured. Automated tests cover selected "
        "pure helpers and voice-intent parsing. Informal peer testing provided qualitative feedback "
        "(navigation clarity, OTP flow, interest in past papers and AI). Because a powered formal "
        "survey was not completed for this write-up, the team does not claim statistical generalisation. "
        "Observed limitations during validation include dependency on backend availability for OTP/AI, "
        "need for Zego credentials for calls, and network sensitivity for large PDF uploads.",
        align="justify",
        first_indent=True,
    )
    add_para(
        doc,
        "Traceability example: FR-01/FR-02 validated via OTP and profile-setup walkthrough; FR-03 via "
        "encrypted send/receive on two devices/emulator sessions; FR-06 via paper upload and open; "
        "FR-08 via AI chat reply; FR-09 via thread create/comment; FR-05 validated when Zego credentials "
        "were supplied, otherwise confirmed disabled-safe behaviour.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "4.9 Chapter Summary", 2)
    add_para(
        doc,
        "The prototype realises an integrated campus messaging and study companion aligned with the "
        "project aim. Module leads delivered balanced thirds of functionality. Chapter 5 discusses "
        "objectives, limitations, and recommendations.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # CHAPTER 5
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "CHAPTER 5: DISCUSSION AND CONCLUSIONS", 1)
    add_heading(doc, "5.1 Introduction", 2)
    add_para(
        doc,
        "This chapter discusses how the implemented system answers the project aim and objectives, "
        "states conclusions, limitations, recommendations, and future work.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "5.2 Discussion Against Objectives", 2)
    add_heading(doc, "5.2.1 Objective 1 — Feature analysis", 3)
    add_para(
        doc,
        "Core messaging and study-platform features were analysed and translated into a concrete module "
        "list. The resulting feature set preserves chat familiarity while adding academic artefacts.",
        align="justify",
        first_indent=True,
    )
    add_heading(doc, "5.2.2 Objective 2 — Architecture", 3)
    add_para(
        doc,
        "A coherent architecture was designed and implemented: Flutter client, Firebase BaaS, Node "
        "OTP/AI edge, Claude provider, and optional Zego. Deviations from the proposal were justified "
        "on security, queryability, and mobile UX grounds.",
        align="justify",
        first_indent=True,
    )
    add_heading(doc, "5.2.3 Objective 3 — Prototype implementation", 3)
    add_para(
        doc,
        "A working prototype covering authentication, messaging, communities/status/calls, papers, "
        "planner, classroom, AI tools, threads, and lecturer routes was produced in the ZCHAT-main "
        "codebase.",
        align="justify",
        first_indent=True,
    )
    add_heading(doc, "5.2.4 Objective 4 — Testing", 3)
    add_para(
        doc,
        "Testing was iterative and partly informal. The proposal’s target of a twenty-student formal "
        "study is acknowledged as incomplete for statistical reporting; honesty here is preferred over "
        "invented metrics. Qualitative feedback supported perceived usefulness of unified chat + papers + AI.",
        align="justify",
        first_indent=True,
    )
    add_heading(doc, "5.2.5 Objective 5 — Documentation", 3)
    add_para(
        doc,
        "This report, the defence presentation, and repository README/config documentation fulfil the "
        "documentation objective, including an explicit equal contribution split.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "5.3 Conclusions", 2)
    add_para(
        doc,
        "UnZA Z CHAT demonstrates that an integrated communication and AI-powered study companion for "
        "Zambian university students is technically feasible using Flutter, Firebase, a Node backend, "
        "and a modern LLM API. The prototype reduces tool fragmentation by placing chat, academic "
        "resources, forums, planner, classroom hooks, and AI assistance in one navigable application. "
        "Equal module ownership among three developers produced a broad but coherent feature surface "
        "suitable for academic demonstration and further productisation.",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "5.4 Limitations", 2)
    add_bullets(
        doc,
        [
            "Formal large-N usability/TAM survey results are not claimed in this report.",
            "AI quality depends on general models and prompt/tool design, not curriculum fine-tuning.",
            "Calls require external Zego credentials; without them, call UI is limited.",
            "OTP/AI require a reachable backend; offline mode is partial (e.g., downloaded papers) rather than full offline chat.",
            "University LMS gradebook integration and official identity federation were not implemented.",
            "Content moderation, spam controls, and production Firestore rule audits need further hardening.",
        ],
    )

    add_heading(doc, "5.5 Recommendations", 2)
    add_bullets(
        doc,
        [
            "Conduct a structured usability and TAM survey with consenting UNZA students and report ethics-approved results.",
            "Partner with departments to seed verified past papers and lecturer accounts.",
            "Complete production security reviews (rules, rate limits, key rotation).",
            "Explore official LMS interoperability for timetables and announcements.",
            "Optimize media/PDF transfers for low-bandwidth campus networks.",
        ],
    )

    add_heading(doc, "5.6 Future Works", 2)
    add_bullets(
        doc,
        [
            "iOS TestFlight / store packaging and accessibility polish.",
            "Stronger offline-first sync for chat metadata and reading lists.",
            "Course-aware AI tools grounded on approved materials with citation UX.",
            "Mobile-money backed optional premium storage or tutoring features.",
            "Analytics dashboards for lecturers (engagement, common AI question themes) with privacy safeguards.",
        ],
    )

    add_heading(doc, "5.7 Chapter Summary", 2)
    add_para(
        doc,
        "The project met its design-and-build aims with an honest account of evaluation status and "
        "limitations. Recommendations chart a path from prototype to sustainable campus deployment.",
        align="justify",
        first_indent=True,
    )

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # REFERENCES
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "REFERENCES", 1)
    refs = [
        "[1] J. L. Whitten, L. D. Bentley, and K. C. Dittman, Systems Analysis and Design Methods, 7th ed. New York, NY, USA: McGraw-Hill, 2007.",
        "[2] StatCounter, “Mobile Operating System Market Share Zambia,” 2026. [Online]. Available: https://gs.statcounter.com/os-market-share/mobile/zambia",
        "[3] ELICATE, “E-learning Platform,” 2026. [Online]. Available: https://elicate.co.zm",
        "[4] F. D. Davis, “Perceived Usefulness, Perceived Ease of Use, and User Acceptance of Information Technology,” MIS Quarterly, vol. 13, no. 3, pp. 319–340, 1989.",
        "[5] M. Phiri and B. Chanda, “Adoption of Mobile Money Services in Lusaka, Zambia: A User Perspective,” Zambian Journal of Information and Communication Technology, vol. 4, no. 1, pp. 45–58, 2022.",
        "[6] K. Hüffner, “Digital Transport in African Cities: The Case of Ride-hailing in Nairobi and Dar es Salaam,” Journal of Transport Geography, vol. 76, pp. 235–243, 2019.",
        "[7] D. Mphanza, “Design and Development of Electronic Record Management System at St Lawrence Parish in Kamwala South Lusaka,” The International Journal of Multi-Disciplinary Research, 2019.",
        "[8] L. Sakala and J. Phiri, “Factors Affecting Adoption of Mobile Banking Services in Zambia Based on the TAM Model,” Open Journal of Business and Management, vol. 7, pp. 1380–1394, 2019.",
        "[9] P. N. Soneka and J. Phiri, “A Model for Improving E-Tax Systems Adoption in Rural Zambia Based on the TAM Model,” Open Journal of Business and Management, vol. 7, pp. 908–918, 2019.",
        "[10] G. C. Daka and J. Phiri, “Factors Driving the Adoption of E-banking Services In Zambia Based on the UTAUT Model,” International Journal of Business and Management, 2019.",
        "[11] I. Sommerville, Software Engineering, 10th ed. Boston, MA, USA: Pearson, 2016.",
        "[12] Y. Kurniawan and C. Cassandra, “Development of a Church Information System,” International Journal of Software Engineering and Its Applications, vol. 8, no. 12, pp. 199–208, 2014.",
        "[13] A. M. King, “Automating Church Accounting,” Management Accounting, Mar. 1998.",
        "[14] F. A. Joko, F. R. R. Anggraini, and B. S. Widodo, “Exploratory Study Based on the Stakeholder Theory in the Development of Accounting Systems in the Catholic Church,” Journal of Information Systems, 2017.",
        "[15] W. C. Metts, “A process for choosing a web-based church management system: a case study,” Journal of Religious Technology, n.d.",
        "[16] N. K. Nee, “Methodist Centre Management System,” Project Report, 2005.",
        "[17] B. M. Kuboye, S. V. Oloja, and O. A. Obolo, “Evaluation of the usage of ICT in Faith-based Organizations: A Case of Selected Churches in AKURE South-North Metropolis,” Journal of Information Systems, 2019.",
        "[18] Google, “Cloud Firestore documentation,” 2026. [Online]. Available: https://firebase.google.com/docs/firestore",
        "[19] Flutter Team, “Flutter documentation,” 2026. [Online]. Available: https://docs.flutter.dev",
        "[20] Anthropic, “Claude API documentation,” 2026. [Online]. Available: https://docs.anthropic.com",
    ]
    for r in refs:
        add_para(doc, r, align="justify", size=11, space_after=6)

    page_break(doc)

    # ═══════════════════════════════════════════════════════════════════════
    # APPENDIX A — Division of Work
    # ═══════════════════════════════════════════════════════════════════════
    add_heading(doc, "APPENDICES", 1)
    add_heading(doc, "Appendix A: Division of Work (Equal Contribution)", 2)
    add_para(
        doc,
        "The three members contributed equally. Innocent Tembo additionally served as group coordinator "
        "(meeting schedules, supervisor liaison, integration oversight) while owning a full third of "
        "feature modules. Student numbers for Ruth Kamwendo and Kewa Lupeke must be filled where blank.",
        align="justify",
        first_indent=True,
    )
    add_para(doc, "Table A.1: Division of work among group members", bold=True, size=11)

    rows = []
    for person, share in ((INNOCENT, "~33%"), (RUTH, "~33%"), (KEWA, "~33%")):
        rows.append(
            [
                person["name"],
                person["id"],
                person["role"],
                "; ".join(person["modules"][:4]) + "; …",
                share,
            ]
        )
    add_table(
        doc,
        ["Member", "Student No.", "Role / ownership", "Key deliverables (summary)", "Share"],
        rows,
        col_widths=[1.3, 1.0, 1.8, 2.2, 0.6],
    )

    add_para(doc, f"Detailed module list — {INNOCENT['name']}:", bold=True)
    add_bullets(doc, INNOCENT["modules"])
    add_para(doc, f"Detailed module list — {RUTH['name']}:", bold=True)
    add_bullets(doc, RUTH["modules"])
    add_para(doc, f"Detailed module list — {KEWA['name']}:", bold=True)
    add_bullets(doc, KEWA["modules"])

    add_heading(doc, "Appendix B: Screenshot Placeholders and User Notes", 2)
    add_para(
        doc,
        "Before final submission/printing, capture screenshots from a configured build and replace the "
        "Figure 4.x placeholders in Chapter 4. Suggested capture list: login/OTP, chat thread, paper "
        "list, AI chat, planner, threads feed, lecturer home. Runtime configuration is documented in "
        "the project README (BACKEND_URL, ZEGO_*, TENOR_KEY).",
        align="justify",
        first_indent=True,
    )

    add_heading(doc, "Appendix C: Contributions Statement for Binding", 2)
    add_para(
        doc,
        "We certify that each member contributed approximately one-third of the project effort across "
        "design, implementation, testing, and documentation of their owned modules, and jointly "
        "authored this report and defence materials.",
        align="justify",
        first_indent=True,
    )
    for person in (INNOCENT, RUTH, KEWA):
        add_para(doc, f"{person['name']} ({person['id']}): __________________ Date: __________", space_after=8)

    doc.save(REPORT_PATH)
    print(f"Wrote {REPORT_PATH}")


# ═══════════════════════════════════════════════════════════════════════════
# POWERPOINT
# ═══════════════════════════════════════════════════════════════════════════

UNZA_GREEN = RGBColor(0x1B, 0x5E, 0x20)
UNZA_DARK = RGBColor(0x21, 0x21, 0x21)
UNZA_ACCENT = RGBColor(0x0D, 0x47, 0xA1)
LIGHT_BG = RGBColor(0xF5, 0xF5, 0xF5)


def _set_shape_text(shape, text, font_size=20, bold=False, color=UNZA_DARK, align=PP_ALIGN.LEFT):
    tf = shape.text_frame
    tf.clear()
    p = tf.paragraphs[0]
    p.alignment = align
    run = p.add_run()
    run.text = text
    run.font.size = PPt(font_size)
    run.font.bold = bold
    run.font.color.rgb = color
    run.font.name = "Calibri"


def _add_title_content_slide(prs, title, bullets, layout_idx=1):
    slide = prs.slides.add_slide(prs.slide_layouts[layout_idx])
    # title
    if slide.shapes.title:
        slide.shapes.title.text = title
        for p in slide.shapes.title.text_frame.paragraphs:
            for r in p.runs:
                r.font.color.rgb = UNZA_GREEN
                r.font.name = "Calibri"
                r.font.bold = True
                r.font.size = PPt(28)
    # content placeholder
    body = None
    for shape in slide.placeholders:
        if shape.placeholder_format.idx == 1:
            body = shape
            break
    if body is None:
        for shape in slide.shapes:
            if shape.has_text_frame and shape != slide.shapes.title:
                body = shape
                break
    if body is not None:
        tf = body.text_frame
        tf.clear()
        for i, item in enumerate(bullets):
            p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
            p.text = item
            p.level = 0
            p.font.size = PPt(18)
            p.font.name = "Calibri"
            p.font.color.rgb = UNZA_DARK
            p.space_after = PPt(8)
    return slide


def _add_blank_titled(prs, title, lines):
    """Title-only layout + textbox body for denser control."""
    slide = prs.slides.add_slide(prs.slide_layouts[5])  # Title Only
    if slide.shapes.title:
        slide.shapes.title.text = title
        for p in slide.shapes.title.text_frame.paragraphs:
            for r in p.runs:
                r.font.color.rgb = UNZA_GREEN
                r.font.name = "Calibri"
                r.font.bold = True
                r.font.size = PPt(26)
    box = slide.shapes.add_textbox(PInches(0.6), PInches(1.5), PInches(9.0), PInches(5.2))
    tf = box.text_frame
    tf.word_wrap = True
    for i, line in enumerate(lines):
        p = tf.paragraphs[0] if i == 0 else tf.add_paragraph()
        p.text = line
        p.font.size = PPt(17)
        p.font.name = "Calibri"
        p.font.color.rgb = UNZA_DARK
        p.space_after = PPt(6)
    return slide


def build_pptx():
    # Start from template to keep dimensions / master; then remove sample slides
    prs = Presentation(str(TEMPLATE_PPT))
    # Remove all existing slides
    xml_slides = prs.slides._sldIdLst
    for sldId in list(xml_slides):
        xml_slides.remove(sldId)

    # Rebuild by opening a fresh presentation with same dimensions
    prs = Presentation()
    prs.slide_width = Emu(9144000)
    prs.slide_height = Emu(6858000)

    # Slide 1 — Cover
    slide = prs.slides.add_slide(prs.slide_layouts[6])  # blank
    # top bar
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, PInches(0), PInches(0), PInches(10), PInches(0.35))
    bar.fill.solid()
    bar.fill.fore_color.rgb = UNZA_GREEN
    bar.line.fill.background()
    title_box = slide.shapes.add_textbox(PInches(0.5), PInches(0.7), PInches(9), PInches(1.2))
    tf = title_box.text_frame
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = "THE UNIVERSITY OF ZAMBIA"
    r.font.size = PPt(22)
    r.font.bold = True
    r.font.color.rgb = UNZA_GREEN
    r.font.name = "Calibri"
    for line, size in [
        ("School of Natural Sciences", 16),
        ("Department of Computing and Informatics", 16),
        ("4th Year Project Presentation — October 2026", 14),
    ]:
        p = tf.add_paragraph()
        p.alignment = PP_ALIGN.CENTER
        r = p.add_run()
        r.text = line
        r.font.size = PPt(size)
        r.font.color.rgb = UNZA_DARK
        r.font.name = "Calibri"

    topic = slide.shapes.add_textbox(PInches(0.5), PInches(2.6), PInches(9), PInches(1.8))
    tf = topic.text_frame
    tf.word_wrap = True
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = "UnZA Z CHAT — An Integrated Communication and AI-Powered Study Companion for Zambian University Students"
    r.font.size = PPt(20)
    r.font.bold = True
    r.font.color.rgb = UNZA_DARK
    r.font.name = "Calibri"

    names = slide.shapes.add_textbox(PInches(0.5), PInches(4.6), PInches(9), PInches(2))
    tf = names.text_frame
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = (
        f"{INNOCENT['name']} ({INNOCENT['id']})\n"
        f"{RUTH['name']} (Student Number: ________)\n"
        f"{KEWA['name']} (Student Number: ________)\n"
        "Supervisor: Prof. J. Phiri"
    )
    r.font.size = PPt(16)
    r.font.color.rgb = UNZA_DARK
    r.font.name = "Calibri"

    # Slide 2 — Title card
    _add_title_content_slide(
        prs,
        "COMPUTER SCIENCE 4TH YEAR PROJECT",
        [
            f"Members: {INNOCENT['name']}, {RUTH['name']}, {KEWA['name']}",
            f"Student ID (lead contact): {INNOCENT['id']}",
            "Supervisor: Prof. J. Phiri",
            "Topic: UnZA Z CHAT — Integrated campus messaging + AI study companion",
            "Equal contribution across three major module streams",
        ],
    )

    _add_title_content_slide(
        prs,
        "PRESENTATION OUTLINE",
        [
            "Introduction & Background",
            "Problem, Aim & Objectives",
            "Literature Review (highlights)",
            "Methodology & Architecture",
            "Implementation / Features (by module owner)",
            "Results & Evaluation approach",
            "Contributions per member",
            "Conclusion, Recommendations & References",
        ],
    )

    _add_title_content_slide(
        prs,
        "INTRODUCTION",
        [
            "Zambian university students rely on WhatsApp-like apps for academic coordination",
            "Past papers, tutoring, and planning remain fragmented across informal channels",
            "UnZA Z CHAT unifies campus messaging with AI-powered study tools in one Flutter app",
            "Group project (3 members) under Prof. J. Phiri — Academic Year 2026",
        ],
    )

    _add_title_content_slide(
        prs,
        "BACKGROUND OF THE STUDY",
        [
            "Digital education tools exist for secondary level (e.g., ELICATE) more than university",
            "Students pay for private tutors or use generic chatbots without course context",
            "Mobile-first delivery fits local device usage patterns",
            "TAM (Davis, 1989): Perceived Usefulness & Ease of Use guide design",
        ],
    )

    _add_title_content_slide(
        prs,
        "STATEMENT OF THE PROBLEM",
        [
            "Communication scattered across multiple apps — hard to retrieve academic info",
            "No central, searchable university past-paper repository",
            "Tutoring costly or generic; weak local course grounding",
            "Study planning rarely integrated with the same app used for collaboration",
        ],
    )

    _add_title_content_slide(
        prs,
        "AIM OF THE STUDY",
        [
            "Design and develop UnZA Z CHAT — a mobile prototype that integrates",
            "WhatsApp-like messaging with an AI-powered study companion",
            "for Zambian university students: communication, past papers,",
            "intelligent tutoring, forums, classroom support, and study planning.",
        ],
    )

    _add_title_content_slide(
        prs,
        "PROJECT OBJECTIVES",
        [
            "1. Analyse messaging & study-platform features for integration",
            "2. Design architecture for chat, papers, AI, forums, planner, classroom",
            "3. Implement Flutter prototype with Firebase + Node backend",
            "4. Evaluate via iterative/manual & informal peer testing (honest scope)",
            "5. Document system, decisions, and equal group contributions",
        ],
    )

    _add_title_content_slide(
        prs,
        "RESEARCH QUESTIONS",
        [
            "How can campus messaging and study tools be combined in one mobile app?",
            "Which architecture supports realtime chat, papers, AI, and forums securely?",
            "What design decisions (Firestore, OTP, Claude) best fit a UNZA prototype?",
            "How should work be divided equally across three developers by module?",
        ],
    )

    _add_title_content_slide(
        prs,
        "LITERATURE REVIEW (1/2)",
        [
            "TAM / UTAUT evidence in Zambia (Sakala & Phiri; Soneka & Phiri; Daka & Phiri)",
            "PU and PEU strongly influence adoption of digital services",
            "Mobile messaging is habitual but not built for academic artefact management",
            "Secondary past-paper platforms leave a university-level gap",
        ],
    )

    _add_title_content_slide(
        prs,
        "LITERATURE REVIEW (2/2) — GAPS",
        [
            "Gap: No local university app combining encrypted chat + papers + AI + forums + planner",
            "Consumer AI apps lack campus identity and course integration",
            "LMS tools often weak on social/realtime mobile chat UX",
            "This project targets the integrated gap with a working prototype",
        ],
    )

    _add_title_content_slide(
        prs,
        "METHODOLOGY",
        [
            "Applied design-and-build; iterative agile increments",
            "Requirements → architecture → vertical slices → polish → docs",
            "Tools: Flutter, Firebase (Auth/Firestore/Storage/FCM), Node.js, Claude, Zego",
            "Evaluation: unit/widget tests + manual QA + informal peer demos",
            "No fabricated survey statistics reported",
        ],
    )

    _add_title_content_slide(
        prs,
        "KEY DESIGN DECISIONS",
        [
            "Firestore (not RTDB) for structured academic + chat documents",
            "Phone OTP + Firebase custom tokens (not email/JWT-only)",
            "Claude via Node proxy (not client-side GPT-3.5 keys)",
            "AES-256-CBC per-chat encryption with fail-closed send",
            "Secrets via --dart-define (ZEGO_*, TENOR_KEY, BACKEND_URL)",
        ],
    )

    _add_title_content_slide(
        prs,
        "SYSTEM ARCHITECTURE",
        [
            "Flutter client (screens + services + go_router)",
            "Firebase: Auth, Firestore, Storage, Cloud Messaging",
            "Node backend: /api/auth (OTP), /api/ai (Claude), notifications",
            "ZegoCloud: voice/video & live classroom media (optional creds)",
            "Roles: Student → /home ; Lecturer → /lecturer/home",
        ],
    )

    _add_title_content_slide(
        prs,
        f"IMPLEMENTATION — {INNOCENT['name'].split()[0].upper()} (Messaging)",
        [
            "Direct & group chat, starred messages, media/location",
            "AES encryption (EncryptionService)",
            "Communities, Status, Presence, Broadcasts",
            "Voice/video calls (CallService + ZegoService)",
            "Also: Group Coordinator (integration & supervisor liaison)",
        ],
    )

    _add_title_content_slide(
        prs,
        f"IMPLEMENTATION — {RUTH['name'].split()[0].upper()} (Academic)",
        [
            "Courses catalogue & UNZA programme data",
            "Past papers upload / list / verify / open PDF",
            "Exam simulator & adaptive learning path screens",
            "Study planner + local notifications",
            "Classroom / live session + lecturer academic screens",
        ],
    )

    _add_title_content_slide(
        prs,
        f"IMPLEMENTATION — {KEWA['name'].split()[0].upper()} (AI & Platform)",
        [
            "OTP auth backend bridge (AuthService)",
            "AI assistant: chat, quiz, summary, insights (Claude)",
            "Voice assistant overlay & intents",
            "ZFeed / Threads forums",
            "FCM + deployment/config (Codemagic, dart-define)",
        ],
    )

    _add_title_content_slide(
        prs,
        "RESULTS & DEMO HIGHLIGHTS",
        [
            "Working flows: OTP → profile → home navigation",
            "Realtime encrypted chat; communities/status/calls (Zego optional)",
            "Course past papers with Storage-backed PDFs",
            "AI tutoring via backend; Threads/ZFeed campus posts",
            "Planner reminders; student & lecturer role streams",
            "Insert live demo / screenshots during defence",
        ],
    )

    _add_title_content_slide(
        prs,
        "EVALUATION APPROACH (HONEST)",
        [
            "Proposal planned ≥20-student formal usability feedback",
            "Completed: iterative QA, selected unit/widget tests, informal peer demos",
            "Not claimed: fabricated SPSS tables or fake adoption percentages",
            "Recommended next: ethics-approved TAM survey with consenting students",
        ],
    )

    _add_title_content_slide(
        prs,
        "CONTRIBUTIONS / DIVISION OF WORK",
        [
            f"{INNOCENT['name']} ({INNOCENT['id']}) — Coordinator + Messaging/Calls/Communities (~33%)",
            f"{RUTH['name']} (________) — Courses/Papers/Planner/Classroom (~33%)",
            f"{KEWA['name']} (________) — Auth-Backend/AI/Threads/Deploy (~33%)",
            "Equal effort; roles mapped to major codebase modules",
            "See report Appendix A for full module lists",
        ],
    )

    _add_title_content_slide(
        prs,
        "CONCLUSION",
        [
            "UnZA Z CHAT shows a feasible integrated campus companion",
            "Flutter + Firebase + Node + Claude is a practical stack for UNZA",
            "Familiar chat UX + academic tools supports TAM-oriented adoption",
            "Prototype ready for demonstration; production hardening remains",
        ],
    )

    _add_title_content_slide(
        prs,
        "RECOMMENDATIONS & FUTURE WORK",
        [
            "Run structured usability / TAM study with UNZA students",
            "Seed verified past papers with departmental partners",
            "Security review of Firestore rules & API rate limits",
            "LMS interoperability; stronger offline-first sync",
            "Course-grounded AI with citation UX; optional iOS packaging",
        ],
    )

    _add_title_content_slide(
        prs,
        "REFERENCES (SELECTED)",
        [
            "Davis (1989) — TAM / MIS Quarterly",
            "Sakala & Phiri (2019) — Mobile banking TAM (Zambia)",
            "Soneka & Phiri (2019) — E-tax TAM (Zambia)",
            "Daka & Phiri (2019) — E-banking UTAUT (Zambia)",
            "Sommerville (2016) — Software Engineering",
            "Whitten et al. — Systems Analysis and Design Methods",
            "Full IEEE-style list in the project report",
        ],
    )

    # Closing slide
    slide = prs.slides.add_slide(prs.slide_layouts[6])
    bar = slide.shapes.add_shape(MSO_SHAPE.RECTANGLE, PInches(0), PInches(0), PInches(10), PInches(0.35))
    bar.fill.solid()
    bar.fill.fore_color.rgb = UNZA_GREEN
    bar.line.fill.background()
    box = slide.shapes.add_textbox(PInches(0.5), PInches(2.2), PInches(9), PInches(3))
    tf = box.text_frame
    p = tf.paragraphs[0]
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = "THANK YOU\nQuestions & Discussion"
    r.font.size = PPt(32)
    r.font.bold = True
    r.font.color.rgb = UNZA_GREEN
    r.font.name = "Calibri"
    p = tf.add_paragraph()
    p.alignment = PP_ALIGN.CENTER
    r = p.add_run()
    r.text = (
        f"\n{INNOCENT['name']} · {RUTH['name']} · {KEWA['name']}\n"
        "Supervisor: Prof. J. Phiri\nUniversity of Zambia — 2026"
    )
    r.font.size = PPt(16)
    r.font.color.rgb = UNZA_DARK
    r.font.name = "Calibri"

    prs.save(str(PPT_PATH))
    print(f"Wrote {PPT_PATH} ({len(prs.slides)} slides)")


def main():
    build_report()
    build_pptx()
    assert REPORT_PATH.exists(), REPORT_PATH
    assert PPT_PATH.exists(), PPT_PATH
    print("OK", REPORT_PATH.stat().st_size, PPT_PATH.stat().st_size)


if __name__ == "__main__":
    main()
