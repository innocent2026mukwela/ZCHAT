# -*- coding: utf-8 -*-
"""Generate UnZA Z CHAT Final Report (docx) and Defence PPT (pptx) from 2026 templates."""
from __future__ import annotations

import copy
import shutil
from pathlib import Path

from docx import Document
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.oxml.ns import qn
from docx.shared import Pt, Inches
from docx.text.paragraph import Paragraph
from pptx import Presentation
from pptx.util import Pt as PPt

TEMPLATE_DOCX = Path(
    r"C:\Users\user\AppData\Local\Temp\CSC-4004-Report-Template"
    r"\Final_Year_Project_Report_Template_2026.docx"
)
TEMPLATE_PPTX = Path(
    r"c:\Users\user\Downloads"
    r"\Final Year Project Defence - Template (Computer Science 4th Years Projects oct2026).pptx"
)
OUT_DOCX = Path(r"c:\Users\user\Desktop\UnZA_Z_CHAT_Final_Report_2026.docx")
OUT_PPTX = Path(r"c:\Users\user\Desktop\UnZA_Z_CHAT_Defence_2026.pptx")

PROJECT_TITLE = (
    "UnZA Z CHAT: An Integrated Campus Messaging and AI Study Companion "
    "for University of Zambia Students"
)
DEGREE = "Bachelor of Science in Computer Science"
SUPERVISOR = "Prof. J. Phiri"
SUBMISSION_DATE = "October 2026"

STUDENTS = [
    ("Innocent Tembo", "2022003055"),
    ("Ruth Kamwendo", "________________"),
    ("Kewa Lupeke", "________________"),
]


# ── docx helpers ──────────────────────────────────────────────────────────────

def delete_paragraph(paragraph: Paragraph) -> None:
    el = paragraph._element
    parent = el.getparent()
    if parent is not None:
        parent.remove(el)


def insert_paragraph_after(paragraph: Paragraph, text: str = "", style: str | None = "Normal") -> Paragraph:
    new_p = copy.deepcopy(paragraph._element)
    # Clear all children of the copied paragraph
    for child in list(new_p):
        new_p.remove(child)
    paragraph._element.addnext(new_p)
    new_para = Paragraph(new_p, paragraph._parent)
    if style:
        try:
            new_para.style = style
        except Exception:
            pass
    if text:
        run = new_para.add_run(text)
        run.font.name = "Times New Roman"
        run._element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
        run.font.size = Pt(12)
    return new_para


def clear_section_body(doc: Document, heading_text: str) -> Paragraph:
    """Find heading (exact or startswith), delete following Normal/List until next Heading."""
    paras = list(doc.paragraphs)
    start = None
    for i, p in enumerate(paras):
        if p.style and p.style.name.startswith("Heading") and (
            p.text.strip() == heading_text or p.text.strip().startswith(heading_text)
        ):
            start = i
            break
    if start is None:
        raise KeyError(f"Heading not found: {heading_text}")

    heading = paras[start]
    # Collect to delete: from start+1 until next Heading 1/2
    to_delete = []
    for j in range(start + 1, len(paras)):
        st = paras[j].style.name if paras[j].style else ""
        if st.startswith("Heading"):
            break
        to_delete.append(paras[j])
    for p in to_delete:
        delete_paragraph(p)
    return heading


def fill_section(doc: Document, heading_text: str, blocks: list[tuple[str, str]]) -> None:
    """blocks: list of (style, text) where style is 'Normal' or 'List Bullet'."""
    heading = clear_section_body(doc, heading_text)
    anchor = heading
    for style, text in blocks:
        anchor = insert_paragraph_after(anchor, text, style=style)


def set_paragraph_text(p: Paragraph, text: str, *, bold: bool | None = None, center: bool = False) -> None:
    # Clear runs
    for r in p.runs:
        r.text = ""
    if not p.runs:
        run = p.add_run(text)
    else:
        p.runs[0].text = text
        run = p.runs[0]
        for extra in p.runs[1:]:
            extra.text = ""
    run.font.name = "Times New Roman"
    try:
        run._element.rPr.rFonts.set(qn("w:eastAsia"), "Times New Roman")
    except Exception:
        pass
    if bold is not None:
        run.bold = bold
    if center:
        p.alignment = WD_ALIGN_PARAGRAPH.CENTER


def add_table_after(paragraph: Paragraph, headers: list[str], rows: list[list[str]]):
    """Insert a simple table after paragraph by adding to document body near element."""
    doc = paragraph.part.document
    table = doc.add_table(rows=1 + len(rows), cols=len(headers))
    table.style = "Table Grid"
    for i, h in enumerate(headers):
        table.rows[0].cells[i].text = h
    for ri, row in enumerate(rows):
        for ci, val in enumerate(row):
            table.rows[ri + 1].cells[ci].text = val
    # Move table XML to after paragraph
    tbl = table._tbl
    paragraph._element.addnext(tbl)
    return table


# ── Content ───────────────────────────────────────────────────────────────────

N = "Normal"
B = "List Bullet"


def report_sections() -> dict[str, list[tuple[str, str]]]:
    """Map heading text -> content blocks. Guidance paragraphs are removed."""
    return {
        "ABSTRACT": [
            (N,
             "University of Zambia (UNZA) students rely on fragmented tools for campus "
             "communication and academic support: consumer messaging apps for peer chat, "
             "scattered PDF repositories for past papers, and ad-hoc notes for study planning. "
             "This final-year project designed, implemented, and evaluated UnZA Z CHAT — a "
             "Flutter mobile application that integrates student messaging (direct chats, "
             "groups, status, communities), campus social threads (ZFeed), course-linked past "
             "papers, an AI study companion (course Q&A, quizzes, summaries), a personal study "
             "planner, and student classroom join/live session participation when configured."),
            (N,
             "The system was built on Flutter with Firebase Authentication, Cloud Firestore, "
             "Firebase Storage, and Firebase Cloud Messaging; a Node.js backend provides OTP "
             "verification (when demo auth is disabled) and AI endpoints that proxy Claude; "
             "ZegoCloud powers voice/video and live classroom sessions when credentials are "
             "supplied. Chat message bodies use per-chat AES-256-CBC encryption that fails "
             "closed. Evaluation used informal prototype testing and walkthroughs of the "
             "student stream (demo authentication, multi-client messaging, papers download "
             "cache, AI reachability messaging, and planner reminders). Formal multi-user UAT "
             "with statistical analysis was not conducted; the completed prototype is ready "
             "for structured acceptance testing with UNZA students."),
            (N,
             "Keywords: campus messaging; AI study companion; Flutter; Firebase; University "
             "of Zambia; student mobile learning"),
        ],
        "ACKNOWLEDGEMENTS": [
            (N,
             "The project team thanks Prof. J. Phiri for supervision and guidance throughout "
             "the design and implementation of UnZA Z CHAT. We thank the Department of "
             "Computing and Informatics, School of Natural and Applied Sciences, University "
             "of Zambia, for academic support. We also acknowledge peers who provided informal "
             "feedback during prototype walkthroughs, and the open-source Flutter and Firebase "
             "communities whose documentation accelerated development."),
        ],
        "TABLE OF CONTENTS": [
            (N,
             "[PLACEHOLDER: In Microsoft Word, place the cursor here and insert an automatic "
             "Table of Contents (References → Table of Contents). Update fields before final "
             "submission so page numbers match the completed chapters.]"),
        ],
        "LIST OF FIGURES": [
            (N, "Figure 3.1  High-level UnZA Z CHAT architecture (client, Firebase, Node AI/OTP, Zego).  [PAGE]"),
            (N, "Figure 4.1  Student navigation map (Chats, ZFeed, Courses, AI, Planner).  [PAGE]"),
            (N, "Figure 4.2  Firestore collections overview for the student stream.  [PAGE]"),
            (N, "Figure 5.1  Student home (Chats / Status / Calls) screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.2  Direct chat and media messages screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.3  ZFeed (threads) screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.4  Courses and past papers screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.5  AI study companion screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.6  Study planner screenshot.  [PLACEHOLDER SCREENSHOT]"),
            (N, "Figure 5.7  Classroom join / live session (student) screenshot.  [PLACEHOLDER SCREENSHOT]"),
        ],
        "LIST OF TABLES": [
            (N, "Table 2.1  Comparison of related campus/messaging approaches.  [PAGE]"),
            (N, "Table 4.1  Selected functional requirements (student stream).  [PAGE]"),
            (N, "Table 4.2  Non-functional requirements.  [PAGE]"),
            (N, "Table 6.1  Representative system test cases and outcomes.  [PAGE]"),
            (N, "Table 6.2  Objective-by-objective evaluation summary.  [PAGE]"),
            (N, "Table A.1  Equal contribution split (group thirds).  [PAGE]"),
        ],
        "LIST OF ABBREVIATIONS AND ACRONYMS": [
            (N, "AES — Advanced Encryption Standard"),
            (N, "AI — Artificial Intelligence"),
            (N, "API — Application Programming Interface"),
            (N, "CBC — Cipher Block Chaining"),
            (N, "FCM — Firebase Cloud Messaging"),
            (N, "FYP — Final Year Project"),
            (N, "OTP — One-Time Password"),
            (N, "PDF — Portable Document Format"),
            (N, "SDK — Software Development Kit"),
            (N, "UAT — User Acceptance Testing"),
            (N, "UI — User Interface"),
            (N, "UNZA — University of Zambia"),
            (N, "UX — User Experience"),
        ],
        "IMPORTANT NOTE ON GROUP PROJECTS": [
            (N,
             "UnZA Z CHAT was completed as a three-member group project with equal overall "
             "contribution (approximately one-third each). This report documents the shared "
             "completed student-stream system. Per departmental guidance, each member should "
             "customise Appendix A (Individual Contribution Statement) to emphasise their "
             "primary third when submitting an individual copy. The equal thirds used for "
             "assessment framing are:"),
            (B, "Innocent Tembo (2022003055) — coordinator; messaging, calls, communities."),
            (B, "Ruth Kamwendo (student number ________) — courses, past papers, planner, student classroom."),
            (B, "Kewa Lupeke (student number ________) — authentication, AI study tools, ZFeed/threads, deployment."),
            (N,
             "Lecturer-facing screens exist in the codebase for future extension but are not "
             "emphasised in this report; the product is framed and evaluated as a student campus app."),
        ],
        # Chapter 1
        "1.1 Background and Context": [
            (N,
             "Digital communication is central to university life. At UNZA, students coordinate "
             "group work, share announcements, locate past examination papers, and seek "
             "explanations for difficult topics. In practice these activities are split across "
             "consumer chat applications, social networks, email, learning portals, and offline "
             "file sharing. Context switching increases friction: a course discussion in one "
             "app is disconnected from the past paper PDF in another and from a study timetable "
             "kept elsewhere."),
            (N,
             "Smartphones are widely available among UNZA students, and cloud backends make it "
             "feasible to deliver real-time messaging and AI assistance without on-campus "
             "server rooms. Prior campus systems often focus on administration or LMS content "
             "delivery rather than peer messaging combined with AI study support. UnZA Z CHAT "
             "was conceived to close that gap for the student stream: one branded campus app "
             "for chats, communities, academic resources, AI Q&A, forums (ZFeed), planning, "
             "and joining classroom sessions."),
        ],
        "1.2 Problem Statement": [
            (N,
             "UNZA students lack a single, campus-oriented mobile application that combines "
             "(i) reliable peer and group messaging with media, status, and communities; "
             "(ii) structured access to course materials such as past papers; "
             "(iii) AI-assisted study support grounded in course context; and "
             "(iv) personal study planning and optional live classroom participation. "
             "Existing consumer apps are not UNZA-aware, do not unify academic artefacts with "
             "chat, and do not provide an institutional path for demo-to-production "
             "authentication and AI backend control. Without an integrated prototype, students "
             "continue to lose time stitching tools together, and the university lacks a "
             "coherent student-facing communication-and-study platform to iterate upon."),
        ],
        "1.3 Project Aim": [
            (N,
             "The aim of this project was to design, implement, and evaluate a completed "
             "student-stream mobile prototype — UnZA Z CHAT — that integrates campus messaging "
             "with AI study companionship and academic support features for University of "
             "Zambia students."),
        ],
        "1.4 Project Objectives": [
            (N, "The project pursued the following objectives:"),
            (B, "Analyse student campus communication and study-support needs and derive functional requirements for a student-only product framing."),
            (B, "Design a client–cloud architecture using Flutter, Firebase, a Node backend for OTP/AI, and optional Zego for real-time media."),
            (B, "Implement student messaging: authentication (including demo OTP), direct/group chats with encrypted bodies, status, communities, and calls when configured."),
            (B, "Implement academic and social study features: courses and past papers, ZFeed threads, AI Q&A/quizzes/summaries via the backend, study planner, and student classroom join."),
            (B, "Integrate Firebase Storage/FCM and fail-closed encryption and clear AI-offline messaging for honest prototype behaviour."),
            (B, "Evaluate the prototype through informal/system testing and document readiness for structured UAT (without inventing uncollected statistics)."),
        ],
        "1.5 Research Questions (where applicable)": [
            (N, "RQ1: How can messaging, academic resources, and AI study tools be integrated in one student mobile app suitable for a UNZA context?"),
            (N, "RQ2: What architecture balances rapid prototyping (Firebase, demo auth) with pathways to production OTP, AI, and optional live media (Zego)?"),
            (N, "RQ3: To what extent does informal prototype testing demonstrate that the student-stream objectives are met, and what remains for formal UAT?"),
        ],
        "1.6 Scope of the Project": [
            (N, "In scope (student stream):"),
            (B, "Phone OTP / demo authentication and student profile setup."),
            (B, "Direct chats, groups, status updates, communities, broadcasts as implemented."),
            (B, "Voice/video calls and live classroom participation when Zego credentials are configured."),
            (B, "Courses catalogue, past paper listing/download cache, exam simulator hooks as implemented."),
            (B, "ZFeed (threads): posts, profiles, search, bookmarks."),
            (B, "AI assistant: chat, quizzes, summaries, group summariser, study insights — requiring Node backend + Claude."),
            (B, "Study planner with local notifications."),
            (B, "Student classroom screens for joining scheduled/live sessions."),
            (N, "Out of scope / de-emphasised:"),
            (B, "Full institutional LMS replacement, payment, or official transcript systems."),
            (B, "Large-scale production hardening, multi-tenant university federation, and formal N-participant SPSS evaluation."),
            (B, "Emphasis on lecturer administration dashboards (present in code for extension only)."),
        ],
        "1.7 Significance of the Project": [
            (N,
             "For students, UnZA Z CHAT reduces tool fragmentation by placing chat, campus "
             "feed, papers, AI help, and planning in one app. For the Department and UNZA, "
             "the prototype demonstrates a feasible modern stack (Flutter + Firebase + Node AI) "
             "and a clear path from demo auth to production OTP. For future cohorts, the "
             "codebase and this report provide a documented baseline for UAT, lecturer-stream "
             "completion, and institutional deployment discussions."),
        ],
        "1.8 Limitations": [
            (B, "Evaluation is informal prototype testing; no fabricated survey N or SPSS results are claimed."),
            (B, "AI features require a reachable Node backend and Claude API configuration; demo login alone does not provide AI."),
            (B, "Voice/video and live class require Zego dart-defines; without them calls remain disabled by design."),
            (B, "Past paper corpus quality depends on uploaded/admin-seeded content in Firebase."),
            (B, "Encryption keys stored on chat documents are protected by Firestore rules but are not end-to-end in the Signal sense."),
            (B, "Network conditions on campus Wi-Fi/mobile data were not systematically stress-tested."),
        ],
        "1.9 Organisation of the Report": [
            (N, "Chapter 2 reviews literature and related systems. Chapter 3 describes methodology and architecture. Chapter 4 presents analysis and design. Chapter 5 documents implementation of the student stream. Chapter 6 reports testing and honest evaluation. Chapter 7 discusses findings. Chapter 8 concludes and recommends future work. Appendices include contribution statements, installation guidance, and supporting material."),
        ],
        # Chapter 2
        "2.1 Introduction": [
            (N,
             "This chapter reviews concepts and related systems that informed UnZA Z CHAT: "
             "campus communication, mobile learning, conversational AI for study, and "
             "real-time mobile backends. It ends with a gap analysis motivating the integrated "
             "student prototype."),
        ],
        "2.2 Key Concepts and Theories": [
            (N,
             "Technology Acceptance Model (TAM) ideas (perceived usefulness and ease of use) "
             "guided UX priorities: familiar chat patterns, clear navigation (Chats, ZFeed, "
             "Courses, AI, Planner), and honest empty/error states when backends are offline."),
            (N,
             "Mobile learning (m-learning) emphasises anytime access to learning resources. "
             "Past papers with local PDF cache and AI Q&A support that orientation."),
            (N,
             "Client–cloud architecture: a Flutter client, managed Firebase services for "
             "auth/data/storage/push, and a controlled Node API for secrets (OTP provider, "
             "Claude keys) keep sensitive credentials off the device."),
            (N,
             "Conversational AI for education: large language models can tutor and summarise, "
             "but require rate limiting, clear failure modes, and institutional policy — hence "
             "backend mediation rather than embedding API keys in the app."),
        ],
        "2.3 Existing Systems / Related Work": [
            (N,
             "Consumer messengers (e.g. WhatsApp) dominate student peer communication but are "
             "not integrated with UNZA courses, past papers, or institutional AI policy."),
            (N,
             "Learning management systems provide courses and files but weak social messaging "
             "and limited mobile-first chat UX."),
            (N,
             "Standalone AI chatbots help with explanations but lack campus identity, group "
             "chat context, and paper repositories."),
            (N,
             "Campus-specific apps elsewhere often cover news or maps; fewer open student "
             "projects combine encrypted chat, ZFeed-style forums, papers, planner, and "
             "backend-mediated Claude assistance as a single Flutter codebase."),
        ],
        "2.4 Comparative Analysis": [
            (N,
             "Table 2.1 (narrative form): Compared with consumer chat, UnZA Z CHAT adds "
             "campus courses/papers, ZFeed, planner, and AI. Compared with an LMS, it adds "
             "real-time student messaging and status. Compared with a generic AI chatbot, it "
             "adds authenticated campus identity, group summariser hooks, and course-scoped "
             "quiz/summary screens. Trade-off: breadth of features increases integration "
             "complexity and dependency on Firebase + Node + optional Zego."),
        ],
        "2.5 Research / Knowledge Gap": [
            (N,
             "The gap addressed is the absence of a UNZA-oriented, student-first mobile "
             "prototype that honestly integrates messaging and AI study tools on a modern "
             "stack, with explicit demo-to-production configuration and fail-closed security "
             "behaviour — documented as a completed FYP artefact rather than a proposal only."),
        ],
        "2.6 Conceptual or Theoretical Framework (where applicable)": [
            (N,
             "The project followed a design-and-build (design science–aligned) framing: "
             "identify the problem of fragmented student tooling; invent an artefact (UnZA Z "
             "CHAT); implement on a justified stack; evaluate against objectives via testing. "
             "TAM informed usability expectations but was not used as a formal survey instrument "
             "in this submission."),
        ],
        "2.7 Chapter Summary": [
            (N,
             "Literature and practice show strong student use of chat and growing AI tutoring, "
             "but weak integration for UNZA. UnZA Z CHAT targets that gap with a Flutter–Firebase–"
             "Node architecture emphasised for the student stream."),
        ],
        # Chapter 3
        "3.1 Introduction": [
            (N,
             "Methodology combined iterative Agile-style development with requirements "
             "driven by the proposal and refined by implementation discoveries (e.g. demo "
             "auth, AI reachability UX, Zego optional)."),
        ],
        "3.2 Research / Development Approach": [
            (N,
             "An iterative incremental approach was used: core auth and Firestore chat first; "
             "then media/status/communities; then courses/papers/planner; then ZFeed; then AI "
             "screens backed by Node; then optional Zego calls/classroom. Continuous manual "
             "regression on Chrome and Android targets accompanied each increment."),
        ],
        "3.3 Requirements / Data Collection": [
            (N,
             "Requirements originated from the project proposal (integrated messaging + AI "
             "study companion), supervisor feedback, and inspection of comparable student "
             "workflows. No large formal survey dataset was collected for this report. Informal "
             "peer walkthroughs guided UX fixes (navigation labels, demo peer discovery, "
             "backend-required AI banners)."),
        ],
        "3.4 System Architecture / Research Workflow": [
            (N,
             "Architecture (Figure 3.1 — describe/insert diagram): Flutter client ↔ Firebase "
             "Auth/Firestore/Storage/FCM for identity, realtime data, media, and push; Flutter "
             "↔ Node backend (BACKEND_URL) for OTP (production) and /api/ai Claude proxy; "
             "Flutter ↔ Zego UIKit when ZEGO_APP_ID/SIGN set for calls/live class. Demo mode "
             "uses local OTP display + Firebase Anonymous Auth with searchable user profiles."),
            (N,
             "[PLACEHOLDER FIGURE 3.1: Insert architecture diagram showing Student App, "
             "Firebase, Node OTP/AI, Claude, Zego.]"),
        ],
        "3.5 Tools and Technologies": [
            (B, "Flutter / Dart — cross-platform client (Android, iOS, web/desktop targets in repo)."),
            (B, "Firebase Auth, Cloud Firestore, Storage, Cloud Messaging."),
            (B, "Node.js backend — OTP and AI API (Claude via server)."),
            (B, "ZegoCloud prebuilt call UI — optional voice/video/live classroom."),
            (B, "go_router, Provider, encrypt/crypto, local notifications, file/image pickers, video_player, speech/TTS as used in modules."),
            (B, "Firestore/Storage security rules deployed from repository."),
        ],
        "3.6 Ethical and Legal Considerations": [
            (N,
             "Student data (phone, name, messages, media) requires privacy care. Demo accounts "
             "are labelled in Firestore. Chat encryption reduces casual exposure of message "
             "bodies in the database console. AI prompts may include user study questions — "
             "API keys remain server-side. The prototype is for academic demonstration; "
             "production deployment would need institutional privacy notice, consent, and "
             "retention policies. Third-party SDKs (Firebase, Zego, Claude) are subject to "
             "their terms."),
        ],
        "3.7 Evaluation Method": [
            (N,
             "Success was measured by: (1) feature completeness against student-stream "
             "objectives; (2) pass/fail manual test cases (auth, chat, papers, AI offline/"
             "online messaging, planner); (3) qualitative walkthrough notes. Structured UAT "
             "surveys and inferential statistics were deferred — recommended as next step, "
             "not claimed as completed."),
        ],
        "3.8 Chapter Summary": [
            (N, "Iterative build on Flutter/Firebase/Node/Zego, with honest evaluation scoped to prototype testing."),
        ],
        # Chapter 4
        "4.1 Introduction": [
            (N, "This chapter records the analysis and design decisions embodied in the completed student-stream system."),
        ],
        "4.2 Stakeholder and User Analysis": [
            (B, "Primary users: UNZA undergraduate students needing chat, resources, AI help, and planning."),
            (B, "Secondary: supervisors/examiners assessing the FYP artefact."),
            (B, "Future: lecturers (not emphasised here), ICT administrators deploying Firebase/Node."),
            (N, "Personas focused on a student joining chats/communities, downloading a past paper, asking the AI tutor, posting on ZFeed, and scheduling study blocks."),
        ],
        "4.3 Functional Requirements": [
            (N, "Selected student-stream functional requirements (Table 4.1 narrative):"),
            (B, "FR1: Register/sign-in via OTP or demo OTP and complete profile."),
            (B, "FR2: Create/open direct and group chats; send text/media; star/delete as implemented."),
            (B, "FR3: Post and view status; browse communities."),
            (B, "FR4: Browse courses and past papers; cache PDFs locally when downloaded."),
            (B, "FR5: Use ZFeed threads (compose, follow feeds, bookmarks, search)."),
            (B, "FR6: Use AI chat/quiz/summary features when backend reachable."),
            (B, "FR7: Manage planner entries and receive local reminders."),
            (B, "FR8: Join classroom/live session flows as a student when sessions exist / Zego configured."),
            (B, "FR9: Place/receive calls when Zego configured; otherwise show disabled/safe behaviour."),
        ],
        "4.4 Non-Functional Requirements": [
            (B, "NFR1 Usability: bottom navigation and familiar chat metaphors."),
            (B, "NFR2 Security: authenticated Firebase access; Storage rules; AES chat bodies fail closed."),
            (B, "NFR3 Reliability: clear errors for Storage/AI/network rather than silent success."),
            (B, "NFR4 Configurability: dart-define for BACKEND_URL, DEMO_AUTH, Zego, Tenor."),
            (B, "NFR5 Maintainability: services layered under lib/services and screens under lib/screens."),
        ],
        "4.5 Use Cases / User Stories": [
            (B, "As a student, I can sign in with demo OTP and find demo peers to chat without a Node OTP server."),
            (B, "As a student, I can message a group and share images/documents stored in Firebase Storage."),
            (B, "As a student, I can open a course past paper and reopen the cached PDF offline-ish on device."),
            (B, "As a student, I can ask the AI assistant a course question when the backend is up."),
            (B, "As a student, I can post on ZFeed and bookmark posts."),
            (B, "As a student, I can add a study plan item and get a local notification."),
            (B, "As a student, I can open a classroom session link/room when scheduled and Zego is configured."),
        ],
        "4.6 System / Solution Architecture": [
            (N,
             "Presentation: Flutter screens + go_router. Domain/services: ChatService, "
             "AuthService, AiService, PapersService, ThreadsService, PlannerService, "
             "CommunitiesService, CallService/ZegoService, FcmService, EncryptionService. "
             "Data: Firestore collections (users, chats/messages, statuses, communities, "
             "courses/papers, threads, planner subcollections). Integration: HTTP to Node; "
             "Zego SDK; FCM."),
        ],
        "4.7 Database / Data Design (where applicable)": [
            (N,
             "Firestore is document-oriented. Key collections include users/{uid} (profile, "
             "demo flag, phoneNumber); chats/{chatId} with messages subcollection and "
             "encryptionKey; user starred/blocked; status; communities; courses and papers "
             "metadata; threads/posts for ZFeed; per-user timetable/studyPlans. Security rules "
             "restrict reads/writes to authenticated members where applicable. "
             "[PLACEHOLDER FIGURE 4.2: ER-style collection diagram.]"),
        ],
        "4.8 Interface / Interaction Design (where applicable)": [
            (N,
             "Student shell: glass-style home with Chats/Status/Calls tabs; bottom nav to "
             "ZFeed, Courses, AI, Planner. Brand lockup uses Space Grotesk. AI screens use "
             "markdown rendering for Claude output. Empty states explain missing backend/Zego "
             "instead of infinite spinners. "
             "[PLACEHOLDER: Insert wireframe or annotated screenshots in Appendix C / Figures 5.x.]"),
        ],
        "4.9 Algorithms / Models / Technical Design": [
            (N,
             "Chat IDs for direct chats are deterministic: sorted uid pair joined by underscore. "
             "AES-256-CBC per chat with key material on the chat document; encrypt failures abort "
             "send. Papers: download once to app documents papers/{id}.pdf and reuse. AI: HTTP "
             "JSON to backend; reachability probe cached ~20s; connectivity failures map to "
             "friendly “AI requires backend” copy. Demo auth: local OTP display + anonymous "
             "Firebase user + profile write for peer discovery."),
        ],
        "4.10 Chapter Summary": [
            (N, "Design centred on a modular Flutter client, Firebase data plane, and Node-controlled AI/OTP, with student UX as the primary product surface."),
        ],
        # Chapter 5
        "5.1 Introduction": [
            (N,
             "Implementation produced a working UnZA Z CHAT application in the ZCHAT "
             "codebase (Flutter package unza_z_chat). This chapter summarises what was built "
             "for the student stream."),
        ],
        "5.2 Development Environment": [
            (B, "Flutter 3.24+ / Dart SDK constrained in pubspec; tested with recent Flutter toolchains."),
            (B, "Firebase project wired via firebase_options and platform config."),
            (B, "Node backend on BACKEND_URL (default http://localhost:5000)."),
            (B, "Editors/IDEs as preferred by members; GitHub repository for collaboration."),
            (B, "Optional Codemagic config present for CI-oriented builds."),
        ],
        "5.3 System Components / Modules": [
            (B, "Auth: login, OTP, profile setup, splash routing to /home for students."),
            (B, "Messaging: chat list/home, chat room, new chat/group, starred, encryption, media upload paths."),
            (B, "Status & calls: status screen; calls UI gated on Zego configuration."),
            (B, "Communities & broadcasts: community list/detail; broadcast screen."),
            (B, "Courses & papers: catalogue, paper list, exam simulator / adaptive plan routes."),
            (B, "Classroom (student): classroom screen and live session screen."),
            (B, "ZFeed: threads feed, detail, search, bookmarks, profiles."),
            (B, "AI: home, chat, quiz, summary, group summariser, study insights."),
            (B, "Planner & profile: timetable/plans/guides services; profile screen."),
        ],
        "5.4 Key Implementation Details": [
            (N,
             "Configuration is centralised in AppConfig (demoAuth default true; backendBase; "
             "zego; tenor). ChatService writes Firestore messages and Storage objects with "
             "user-visible Storage error mapping. EncryptionService fails closed. AiService "
             "never pretends success when the API is down. PapersService caches PDFs. "
             "PlannerService uses flutter_local_notifications and timezone. Student bottom "
             "navigation intentionally highlights Chats, zFeed, Courses, AI, Planner."),
            (N,
             "Deviations from early proposal ideas (e.g. stronger lecturer UX, always-on "
             "calls) were accepted as justified: optional Zego avoids broken call UX without "
             "keys; demo auth enables multi-device messaging demos without SMS cost; AI "
             "backend separation protects API keys."),
        ],
        "5.5 Integration": [
            (N,
             "Integration points: Firebase init in main; auth state to router; FCM service "
             "registration; HTTP AI with Firebase ID tokens where required by backend; Zego "
             "service checks AppConfig.zegoConfigured; Storage rules must be deployed for "
             "media. Multi-client demo requires the same Firebase project and distinct phones/"
             "profiles."),
        ],
        "5.6 Challenges and Solutions": [
            (B, "Challenge: OTP SMS cost/complexity in student demos → Solution: DEMO_AUTH local OTP + anonymous auth."),
            (B, "Challenge: AI hanging when backend down → Solution: reachability probe + AiBackendRequired UI."),
            (B, "Challenge: Calls crashing without credentials → Solution: gate on zegoConfigured."),
            (B, "Challenge: Plaintext risk in Firestore → Solution: AES per chat, fail closed."),
            (B, "Challenge: Past paper re-download cost → Solution: local file cache by paper id."),
            (B, "Challenge: Scope creep from lecturer features → Solution: keep code paths but report/defend student stream."),
        ],
        "5.7 Individual Contribution (group projects)": [
            (N, "Equal overall contribution (~33% each). Primary thirds:"),
            (B, "Innocent Tembo (2022003055): coordination; messaging, calls, communities modules."),
            (B, "Ruth Kamwendo (________): courses, past papers, study planner, student classroom join/flows."),
            (B, "Kewa Lupeke (________): authentication, AI study companion integration, ZFeed/threads, deployment/config."),
            (N, "Shared: requirements workshops, integration testing, report/defence preparation. See Appendix A."),
        ],
        "5.8 Chapter Summary": [
            (N, "The student-stream application was implemented as a modular Flutter client with Firebase and Node/Zego integrations matching the design."),
        ],
        # Chapter 6
        "6.1 Introduction": [
            (N,
             "Testing verified that implemented student features behave correctly under "
             "demo and backend-connected conditions. Results are qualitative/prototype-level."),
        ],
        "6.2 Testing Strategy": [
            (B, "Unit/widget: selective flutter_test usage where present; primarily manual."),
            (B, "Integration: two-client demo chat on same Firebase project."),
            (B, "System: end-to-end walks of nav destinations."),
            (B, "Negative tests: AI with backend stopped; calls without Zego; Storage rules missing."),
            (B, "Usability: informal peer walkthroughs (not a formal usability lab study)."),
        ],
        "6.3 Test Cases and Results": [
            (N, "Table 6.1 — Representative cases (Pass = observed correct behaviour in prototype runs):"),
            (B, "TC01 Demo login shows OTP and accepts 6-digit code → Pass."),
            (B, "TC02 Profile setup writes searchable user doc → Pass."),
            (B, "TC03 Demo peers list opens direct chat; message syncs on second client → Pass."),
            (B, "TC04 Group create and member message → Pass (subject to privacy settings)."),
            (B, "TC05 Image/status upload with rules deployed → Pass; without rules → clear error (Pass for fail-closed UX)."),
            (B, "TC06 Past paper download then reopen from cache → Pass."),
            (B, "TC07 AI screens with backend down show backend-required message → Pass."),
            (B, "TC08 AI chat with backend up returns assistant message → Pass (when Claude/backend configured)."),
            (B, "TC09 Planner item schedules local notification path → Pass on supported platforms tested."),
            (B, "TC10 Calls entry without Zego does not claim live media → Pass (disabled/safe)."),
            (B, "TC11 ZFeed compose appears on feed → Pass."),
            (B, "TC12 Student classroom route opens for course id → Pass (live media depends on Zego/session data)."),
        ],
        "6.4 Experimental Results / Performance Results (where applicable)": [
            (N,
             "No formal load-test metrics (messages/sec, p95 latency) were collected for this "
             "submission. Qualitatively, Firestore snapshot chats felt interactive on Wi-Fi "
             "during demos. Performance characterisation is recommended for UAT/production."),
        ],
        "6.5 User Evaluation (where applicable)": [
            (N,
             "Informal feedback from peer walkthroughs indicated that combining chat with "
             "courses/AI in one nav bar was valued, and that demo peer discovery was essential "
             "for marking demos. No questionnaire statistics are reported because a structured "
             "instrument was not administered at scale."),
        ],
        "6.6 Analysis of Results": [
            (N,
             "Results support that the prototype meets core student-stream objectives under "
             "stated configuration assumptions. Failures were mainly environmental (backend "
             "down, rules not deployed, Zego unset) and were surfaced honestly — an intentional "
             "quality attribute for academic demonstration."),
        ],
        "6.7 Objective-by-Objective Evaluation": [
            (B, "Obj. analyse requirements — Achieved: documented FR/NFR and student framing."),
            (B, "Obj. architecture — Achieved: Flutter–Firebase–Node–optional Zego implemented."),
            (B, "Obj. messaging — Achieved: chats/groups/status/communities; calls when configured."),
            (B, "Obj. academic/social/AI/planner/classroom — Achieved at prototype level as implemented in routes/services."),
            (B, "Obj. security/config honesty — Achieved: encryption fail-closed; AI/Zego messaging."),
            (B, "Obj. evaluation — Partially achieved: informal tests complete; formal UAT pending."),
        ],
        "6.8 Individual Results (group projects)": [
            (N,
             "Each third delivered working modules integrated into the single app binary. "
             "Integration milestones (shared Firebase project, router, nav) were joint. "
             "Individual deep results map to the modules listed in §5.7."),
        ],
        "6.9 Chapter Summary": [
            (N, "Prototype testing indicates a completed student-stream system ready for structured UAT; no fake statistical claims are made."),
        ],
        # Chapter 7
        "7.1 Introduction": [
            (N, "Discussion interprets the completed artefact relative to the problem, literature, and limitations."),
        ],
        "7.2 Interpretation of Findings": [
            (N,
             "Integrating messaging with study tools is technically feasible on Flutter/Firebase "
             "within an FYP timeframe when scope is student-first and optional subsystems "
             "(Zego, Claude) are configuration-gated. Honest degradation improved demo "
             "reliability versus claiming features that cannot run without secrets."),
        ],
        "7.3 Comparison with Existing Work": [
            (N,
             "Relative to consumer chat, UnZA Z CHAT adds campus academic context. Relative "
             "to LMS apps, it adds realtime social messaging and AI companion screens. The "
             "novelty for this FYP is the UNZA-oriented integrated prototype and documented "
             "stack choices, not a new encryption protocol or LLM architecture."),
        ],
        "7.4 Contributions of the Project": [
            (B, "A completed student campus app prototype: messaging + ZFeed + papers + AI + planner + classroom join."),
            (B, "Practical pattern for demo auth and production OTP/AI backend separation."),
            (B, "Fail-closed chat encryption and explicit offline AI UX."),
            (B, "Equal-thirds team delivery with clear module ownership."),
        ],
        "7.5 Limitations and Implications": [
            (N,
             "Without formal UAT, adoption claims remain provisional. Encryption is not full "
             "E2EE against a compromised backend/rules. AI answers require academic integrity "
             "policies before wide release. Implications: treat the system as a strong "
             "prototype for departmental pilot, not yet a production UNZA service."),
        ],
        "7.6 Chapter Summary": [
            (N, "Findings support problem–solution fit at prototype level, with clear next steps for evaluation and policy."),
        ],
        # Chapter 8
        "8.1 Introduction": [
            (N, "This chapter concludes the UnZA Z CHAT final-year project and recommends next actions."),
        ],
        "8.2 Summary of the Project": [
            (N,
             "The team identified fragmented student communication/study tooling at UNZA, "
             "designed a Flutter–Firebase–Node architecture, implemented a student-stream "
             "application with messaging, ZFeed, courses/papers, AI companion, planner, and "
             "classroom join, and evaluated it through informal prototype testing."),
        ],
        "8.3 Conclusions": [
            (N,
             "UnZA Z CHAT demonstrates that an integrated student campus messaging and AI "
             "study companion can be delivered as a coherent mobile prototype. Configuration-"
             "gated calls/AI and demo authentication were essential engineering decisions for "
             "a credible completed FYP demo."),
        ],
        "8.4 Achievement of Objectives": [
            (N, "All implementation objectives for the student stream were achieved at prototype completeness. The evaluation objective was achieved for informal testing and explicitly left formal UAT as future work."),
        ],
        "8.5 Recommendations": [
            (B, "Conduct structured UAT with UNZA students (ethics approval, consent, instrument) before production claims."),
            (B, "Deploy Storage/Firestore rules and production OTP provider; set DEMO_AUTH=false for pilots."),
            (B, "Define AI usage guidelines (academic integrity, logging, moderation)."),
            (B, "Seed a curated past-paper library per programme."),
            (B, "Only enable Zego in environments with funded credentials and network capacity."),
        ],
        "8.6 Future Work": [
            (B, "Complete and evaluate lecturer stream if the department prioritises it."),
            (B, "Stronger E2EE / key management; message moderation tools."),
            (B, "Offline-first sync improvements; accessibility audit."),
            (B, "Performance and security penetration testing for production readiness."),
            (B, "Institutional single sign-on if UNZA identity services become available."),
        ],
        "REFERENCES": [
            (N, "Davis, F. D. (1989). Perceived usefulness, perceived ease of use, and user acceptance of information technology. MIS Quarterly, 13(3), 319–340."),
            (N, "Firebase. (n.d.). Firebase documentation. Google. https://firebase.google.com/docs"),
            (N, "Flutter. (n.d.). Flutter documentation. Google. https://docs.flutter.dev"),
            (N, "Anthropic. (n.d.). Claude API documentation. https://docs.anthropic.com"),
            (N, "ZegoCloud. (n.d.). Zego UIKit / call documentation. https://www.zegocloud.com"),
            (N, "Kearney, M., Schuck, S., Burden, K., & Aubusson, P. (2012). Viewing mobile learning from a pedagogical perspective. Research in Learning Technology, 20(1)."),
            (N, "University of Zambia, Department of Computing and Informatics. (2026). Final Year Project Report Template."),
            (N, "WhatsApp. (n.d.). Features overview (consumer messaging baseline comparison). Meta."),
            (N, "[PLACEHOLDER: Add any proposal-cited local UNZA sources, lecture notes, or additional papers used in your literature chapter.]"),
        ],
        # Appendices
        "APPENDIX A: INDIVIDUAL CONTRIBUTION STATEMENT (GROUP PROJECTS)": [
            (N, "Purpose of this Statement"),
            (N, "This statement documents equal contribution for the UnZA Z CHAT group project. Each student should sign an individual copy emphasising their primary third."),
            (N, "Project and Group Information"),
            (N, f"Project Title: {PROJECT_TITLE}"),
            (N, "Students: Innocent Tembo (2022003055); Ruth Kamwendo (________); Kewa Lupeke (________). Supervisor: Prof. J. Phiri. Academic Year: 2026."),
            (N, "Overall Group Project"),
            (N, "UnZA Z CHAT is an integrated student campus messaging and AI study companion for UNZA, delivered as one Flutter application with Firebase and Node backend services."),
            (N, "Individual Role and Responsibilities (equal thirds)"),
            (B, "Innocent Tembo — Coordinator; messaging (chats/groups/status), calls integration, communities."),
            (B, "Ruth Kamwendo — Courses, past papers, study planner, student classroom."),
            (B, "Kewa Lupeke — Auth (incl. demo), AI study tools + Node integration, ZFeed/threads, deploy/config."),
            (N, "Detailed Individual Contribution"),
            (N, "See module lists in Chapter 5. Joint work included architecture decisions, integration testing on shared Firebase, and documentation."),
            (N, "Individual Deliverables"),
            (B, "Working student app modules merged to main codebase."),
            (B, "Firebase rules and configuration documentation in README."),
            (B, "This final report and defence presentation (shared)."),
            (N, "Contribution Summary"),
            (N, "(1) Primary individual modules as per thirds above; (2) Joint integration, QA, and docs; (3) Cross-use of each other’s modules inside one APK/app."),
            (N, "Estimated Contribution (equal overall ≈ 33% each across the project)"),
            (N, "Problem Analysis: 30% individual focus / 70% collaborative (all)."),
            (N, "Literature Review: 30% / 70%."),
            (N, "Requirements: 30% / 70%."),
            (N, "Design: 30% / 70%."),
            (N, "Implementation: ~33% each on owned modules; integration collaborative."),
            (N, "Testing: 30% / 70%."),
            (N, "Documentation: 30% / 70%."),
            (N, "Statement of Authorship and Contribution"),
            (N, "I confirm that the contribution described accurately represents my work as part of the equal-thirds team."),
            (N, "Student Name: ______________________________________"),
            (N, "Computer Number: ____________________________________"),
            (N, "Signature: ___________________________________________"),
            (N, "Date: _______________________________________________"),
            (N, "Supervisor Verification"),
            (N, "I confirm that, to the best of my knowledge, the contribution described is consistent with the student's participation."),
            (N, "Supervisor Name: Prof. J. Phiri ______________________"),
            (N, "Signature: ___________________________________________"),
            (N, "Date: _______________________________________________"),
        ],
        "APPENDIX B: USER MANUAL / INSTALLATION GUIDE": [
            (N, "Prerequisites: Flutter 3.24+; Firebase project configured; optional Node backend; optional Zego credentials."),
            (N, "Install: clone repository; flutter pub get."),
            (N, "Run (Chrome): flutter run -d chrome --dart-define=BACKEND_URL=http://localhost:5000"),
            (N, "Demo auth is ON by default. Sign in with phone; enter displayed OTP (any 6 digits in demo); complete profile."),
            (N, "Two-client chat: two devices/browsers, same Firebase, different phones/names; New Chat → Demo peers."),
            (N, "AI: start Node API; otherwise AI screens show backend required."),
            (N, "Calls/live: pass ZEGO_APP_ID and ZEGO_APP_SIGN."),
            (N, "Storage: firebase deploy --only storage using repo storage.rules."),
            (N, "Production OTP: --dart-define=DEMO_AUTH=false with backend OTP configured."),
            (N, "Troubleshooting: check BACKEND_URL for emulators (10.0.2.2); confirm Firebase options; read on-screen Storage/AI errors."),
        ],
        "APPENDIX C: ADDITIONAL SYSTEM DESIGNS / DIAGRAMS": [
            (N, "[PLACEHOLDER: Insert architecture diagram, navigation map, and Firestore collection diagram here.]"),
            (N, "[PLACEHOLDER: Optional UML use-case diagram for student actors.]"),
        ],
        "APPENDIX D: ADDITIONAL TEST CASES AND RESULTS": [
            (N, "Extend Table 6.1 with device-specific notes (Android emulator, Chrome, physical device) as you run final demos."),
            (N, "[PLACEHOLDER: Paste screenshots of passed TC01–TC12 with dates.]"),
        ],
        "APPENDIX E: DATA COLLECTION INSTRUMENTS": [
            (N, "No formal questionnaire was administered for statistical analysis in this submission."),
            (N, "[PLACEHOLDER FOR UAT]: Draft Likert items on usefulness/ease of use (TAM-inspired) for future ethics-approved study — do not fabricate completed responses."),
        ],
        "APPENDIX F: ADDITIONAL CODE / CONFIGURATION": [
            (N, "See repository: lib/config.dart (dart-defines); lib/services/*; firestore.rules; storage.rules; README.md run instructions."),
            (N, "GitHub: https://github.com/innocent2026mukwela/ZCHAT (and/or local ZCHAT-main)."),
            (N, "[PLACEHOLDER: Optionally paste short excerpts of EncryptionService encrypt API and AiService reachability — not the full codebase.]"),
        ],
        "APPENDIX G: OTHER SUPPORTING MATERIAL": [
            (N, "[PLACEHOLDER: Supervisor meeting logs, sprint notes, ethics forms if required.]"),
            (N, "[PLACEHOLDER: High-resolution screenshots for defence demo backup.]"),
        ],
    }


CHAPTER_INTROS = {
    "CHAPTER 1: INTRODUCTION": (
        "This chapter introduces the completed UnZA Z CHAT project: background, problem, "
        "aim, objectives, scope, significance, limitations, and report organisation. The "
        "tone reflects work that was implemented and informally evaluated, not merely proposed."
    ),
    "CHAPTER 2: LITERATURE REVIEW": (
        "This chapter reviews concepts and related systems that shaped the student-stream "
        "design of UnZA Z CHAT and identifies the knowledge gap addressed by the prototype."
    ),
    "CHAPTER 3: METHODOLOGY": (
        "This chapter explains how the project was conducted: iterative development, "
        "architecture, tools, ethics, and evaluation method."
    ),
    "CHAPTER 4: SYSTEM ANALYSIS AND DESIGN": (
        "This chapter presents stakeholders, requirements, use cases, architecture, data "
        "design, interfaces, and key technical design decisions for the student stream."
    ),
    "CHAPTER 5: IMPLEMENTATION / DEVELOPMENT": (
        "This chapter describes the implemented UnZA Z CHAT student application modules, "
        "integrations, challenges, and equal group contributions."
    ),
    "CHAPTER 6: TESTING, RESULTS AND EVALUATION": (
        "This chapter reports prototype testing strategy, representative test cases, honest "
        "evaluation limits, and objective-by-objective assessment."
    ),
    "CHAPTER 7: DISCUSSION": (
        "This chapter interprets findings, relates them to existing work, and states "
        "contributions and limitations."
    ),
    "CHAPTER 8: CONCLUSION AND RECOMMENDATIONS": (
        "This chapter summarises the project, states conclusions, confirms objective "
        "achievement, and recommends future work including structured UAT."
    ),
}


def fill_front_matter(doc: Document) -> None:
    # Title page paragraphs by known indices from template dump
    mapping = {
        8: PROJECT_TITLE,
        13: DEGREE,
        15: "By",
        16: (
            f"{STUDENTS[0][0]} ({STUDENTS[0][1]})\n"
            f"{STUDENTS[1][0]} ({STUDENTS[1][1]})\n"
            f"{STUDENTS[2][0]} ({STUDENTS[2][1]})"
        ),
        17: "Equal contribution group project (see Appendix A)",
        19: f"Supervisor: {SUPERVISOR}",
        20: f"Date of Submission: {SUBMISSION_DATE}",
    }
    for idx, text in mapping.items():
        if idx < len(doc.paragraphs):
            set_paragraph_text(doc.paragraphs[idx], text, center=(idx in (8, 13, 15, 16, 17)))

    # Declaration names lines — leave signature blanks but identify group
    # Find "Student Name:" after DECLARATION
    for i, p in enumerate(doc.paragraphs):
        if p.text.strip() == "Student Name:" and i < 40:
            # following lines are underscores — add names note in declaration body already filled
            break

    # Fill declaration body (non-guidance)
    # Abstract keywords already in ABSTRACT section fill


def strip_guidance_globally(doc: Document) -> None:
    """Remove any remaining GUIDANCE paragraphs left in unused spots."""
    for p in list(doc.paragraphs):
        t = p.text.strip()
        if t.startswith("[GUIDANCE:") or t == "[Write this section here.]" or t == "[Write the abstract here.]" or t == "[Write acknowledgements here.]" or t == "[Insert references here.]" or t == "[Insert material here.]" or t.startswith("[Generate or complete"):
            # only delete if not already replaced — fill_section removes most
            if t.startswith("[GUIDANCE:") or t in {
                "[Write this section here.]",
                "[Write the abstract here.]",
                "[Write acknowledgements here.]",
                "[Insert references here.]",
                "[Insert material here.]",
            } or t.startswith("[Generate or complete"):
                delete_paragraph(p)


def build_report() -> None:
    shutil.copy2(TEMPLATE_DOCX, OUT_DOCX)
    doc = Document(str(OUT_DOCX))
    fill_front_matter(doc)

    # Chapter intro guidance replacements
    for heading, intro in CHAPTER_INTROS.items():
        try:
            # Clear only the first Normal after heading if it's guidance / placeholder
            paras = list(doc.paragraphs)
            for i, p in enumerate(paras):
                if p.text.strip() == heading:
                    # delete following until Heading 2
                    j = i + 1
                    while j < len(paras):
                        st = paras[j].style.name if paras[j].style else ""
                        if st.startswith("Heading"):
                            break
                        nxt = paras[j]
                        j += 1
                        delete_paragraph(nxt)
                    insert_paragraph_after(paras[i], intro, N)
                    break
        except Exception as e:
            print("chapter intro warn", heading, e)

    sections = report_sections()
    for heading, blocks in sections.items():
        try:
            fill_section(doc, heading, blocks)
        except KeyError as e:
            print("MISSING", e)

    # Declaration / Approval keep structure; replace guidance-only lines
    for p in list(doc.paragraphs):
        t = p.text.strip()
        if t.startswith("[GUIDANCE:"):
            delete_paragraph(p)

    # Strengthen declaration for group
    for i, p in enumerate(doc.paragraphs):
        if p.text.strip().startswith("I declare that this final year project report"):
            set_paragraph_text(
                p,
                "We declare that this final year project report is our own work as a group "
                "and has been prepared in accordance with the academic requirements of the "
                "University of Zambia. All sources of information, ideas, data, software, "
                "images, and other material that are not our own have been appropriately "
                "acknowledged and referenced. Individual contributions are identified in "
                "Appendix A (equal thirds).",
            )
        if p.text.strip().startswith("Where this project was undertaken"):
            set_paragraph_text(
                p,
                "This project was undertaken as a group. We have clearly identified individual "
                "contributions and have not presented another member's exclusive work as our "
                "own. Each member may submit a signed individual Appendix A emphasising their primary third.",
            )

    strip_guidance_globally(doc)
    doc.save(str(OUT_DOCX))
    print("Wrote", OUT_DOCX)


# ── PPT ───────────────────────────────────────────────────────────────────────

def set_shape_text(shape, text: str) -> None:
    if not shape.has_text_frame:
        return
    tf = shape.text_frame
    # Put all text in first paragraph; clear others
    lines = text.split("\n")
    # Clear
    for pi, para in enumerate(tf.paragraphs):
        if pi == 0:
            if para.runs:
                para.runs[0].text = lines[0] if lines else ""
                for r in para.runs[1:]:
                    r.text = ""
            else:
                para.text = lines[0] if lines else ""
        else:
            for r in para.runs:
                r.text = ""
            para.text = ""
    # Add remaining lines as new paragraphs if needed
    first = tf.paragraphs[0]
    # If bullet-like multi-line, recreate simply
    if len(lines) > 1:
        # Reset entire frame text
        tf.clear()
        for i, line in enumerate(lines):
            if i == 0:
                p = tf.paragraphs[0]
            else:
                p = tf.add_paragraph()
            p.text = line
            p.level = 0
            for run in p.runs:
                run.font.size = PPt(16)


def set_slide_body(slide, title: str | None, body: str) -> None:
    # Title is usually shapes[0]; body is first content placeholder with text frame
    if title is not None:
        for shape in slide.shapes:
            if shape.has_text_frame and shape == slide.shapes.title:
                set_shape_text(shape, title)
                break
        else:
            # fallback first text shape
            for shape in slide.shapes:
                if shape.has_text_frame:
                    set_shape_text(shape, title)
                    break
    # Body: largest / content placeholder
    body_shape = None
    for shape in slide.shapes:
        if not shape.has_text_frame:
            continue
        if slide.shapes.title is not None and shape == slide.shapes.title:
            continue
        name = (shape.name or "").lower()
        if "content" in name or "subtitle" in name or "placeholder" in name:
            body_shape = shape
            break
    if body_shape is None:
        # pick second text frame
        texts = [s for s in slide.shapes if s.has_text_frame]
        if slide.shapes.title in texts:
            texts = [s for s in texts if s != slide.shapes.title]
        if texts:
            body_shape = texts[0]
    if body_shape is not None:
        set_shape_text(body_shape, body)


def build_defence() -> None:
    shutil.copy2(TEMPLATE_PPTX, OUT_PPTX)
    prs = Presentation(str(OUT_PPTX))
    slides = list(prs.slides)

    # Slide 1 — institutional (keep mostly; tighten subtitle)
    set_slide_body(
        slides[0],
        "THE UNIVERSITY OF ZAMBIA\nSchool of Natural Sciences\nDepartment of Computer Science",
        "4th Year Project Presentation | October 2026\nUnZA Z CHAT — Student Stream",
    )

    # Slide 2 — title with all 3 names
    names = (
        f"NAMES: {STUDENTS[0][0]} ({STUDENTS[0][1]}); "
        f"{STUDENTS[1][0]} ({STUDENTS[1][1]}); "
        f"{STUDENTS[2][0]} ({STUDENTS[2][1]})"
    )
    # Fill multiple subtitle shapes carefully
    for shape in slides[1].shapes:
        if not shape.has_text_frame:
            continue
        t = shape.text_frame.text
        if "COMPUTER SCIENCE" in t or "4TH YEAR" in t:
            set_shape_text(shape, "COMPUTER SCIENCE\n4TH YEAR PROJECT PRESENTATION")
        elif "NAME:" in t or "STUDENT ID" in t or "SUPERVISOR" in t:
            set_shape_text(
                shape,
                f"{names}\nSUPERVISOR: {SUPERVISOR}",
            )
        elif "Topic:" in t or "Smart" in t or "Hand" in t:
            set_shape_text(
                shape,
                "Topic: UnZA Z CHAT — Integrated Campus Messaging &\nAI Study Companion (Student Stream)",
            )

    set_slide_body(
        slides[2],
        "PRESENTATION OUTLINE",
        "Introduction\n"
        "Background of the study\n"
        "Statement of the problem\n"
        "Aim of the Study\n"
        "Project Objectives\n"
        "Literature Review\n"
        "Methodology\n"
        "Project Results and Discussion\n"
        "Team Contributions (equal thirds)\n"
        "Conclusion and Recommendations\n"
        "References",
    )

    set_slide_body(
        slides[3],
        "INTRODUCTION",
        "UNZA students juggle chat apps, PDFs, and notes for campus life\n"
        "UnZA Z CHAT unifies student messaging + study support in one app\n"
        "Completed Flutter prototype with Firebase + Node AI backend\n"
        "Framed as a student campus product (not lecturer admin)",
    )

    set_slide_body(
        slides[4],
        "BACKGROUND OF THE STUDY",
        "Mobile-first students need realtime peer communication\n"
        "Academic success also needs past papers, planning, and help-on-demand\n"
        "Cloud backends (Firebase) + LLM APIs enable campus prototypes quickly\n"
        "TAM-inspired UX: useful, easy, familiar chat patterns",
    )

    set_slide_body(
        slides[5],
        "STATEMENT OF THE PROBLEM",
        "No single UNZA-oriented student app combining:\n"
        "• Chats, groups, status, communities\n"
        "• Courses / past papers + planner\n"
        "• AI study Q&A (policy-controlled backend)\n"
        "• Campus feed (ZFeed) + classroom join\n"
        "Fragmentation wastes time and blocks institutional iteration",
    )

    set_slide_body(
        slides[6],
        "AIM OF THE STUDY",
        "To design, implement, and evaluate UnZA Z CHAT —\n"
        "a completed student-stream mobile prototype integrating\n"
        "campus messaging with an AI study companion\n"
        "for University of Zambia students.",
    )

    set_slide_body(
        slides[7],
        "RESEARCH OBJECTIVES",
        "1. Analyse student requirements for an integrated campus app\n"
        "2. Design Flutter–Firebase–Node–(optional) Zego architecture\n"
        "3. Implement messaging, ZFeed, papers, AI, planner, classroom join\n"
        "4. Apply fail-closed encryption + honest offline AI/call behaviour\n"
        "5. Evaluate via prototype testing; prepare for structured UAT",
    )

    set_slide_body(
        slides[8],
        "LITERATURE REVIEW (1/3)",
        "Consumer messengers: strong chat, weak campus academics\n"
        "LMS apps: content-heavy, weaker social realtime chat\n"
        "Standalone AI tutors: helpful, but no campus identity/context\n"
        "Need: integrated student-first UNZA prototype",
    )

    set_slide_body(
        slides[9],
        "LITERATURE REVIEW (2/3)",
        "m-learning: anytime access to resources (papers, AI help)\n"
        "Client–cloud: keep OTP/Claude secrets on Node server\n"
        "Realtime data: Firestore snapshots for chat/feed\n"
        "Optional WebRTC-style media via Zego when funded/configured",
    )

    set_slide_body(
        slides[10],
        "LITERATURE REVIEW (3/3)",
        "Gap: UNZA student app with chat + papers + AI + feed + planner\n"
        "Our response: UnZA Z CHAT completed prototype\n"
        "Design deviations OK if justified (demo auth, gated Zego)",
    )

    set_slide_body(
        slides[11],
        "RESEARCH METHODOLOGY (1/4)",
        "Approach: iterative Agile increments\n"
        "Stack: Flutter client; Firebase Auth/Firestore/Storage/FCM\n"
        "Node backend: OTP (prod) + Claude AI proxy\n"
        "Zego: voice/video/live class when dart-defines set\n"
        "Demo auth default for cost-free multi-client demos",
    )

    set_slide_body(
        slides[12],
        "RESEARCH METHODOLOGY (2/4)",
        "Student IA: Chats | ZFeed | Courses | AI | Planner\n"
        "Services layer: Chat, AI, Papers, Threads, Planner, Communities…\n"
        "AES-256-CBC per-chat encryption (fail closed)\n"
        "PDF past-paper local cache\n"
        "[Diagram placeholder in report Appendix C]",
    )

    set_slide_body(
        slides[13],
        "RESEARCH METHODOLOGY (3/4)",
        "Data: Firestore collections (users, chats, threads, courses…)\n"
        "Media: Firebase Storage + deployed rules\n"
        "Security: Auth required; rules; no plaintext send on encrypt fail\n"
        "Ethics: demo labels; server-side AI keys; future privacy notice",
    )

    set_slide_body(
        slides[14],
        "RESEARCH METHODOLOGY (4/4)",
        "Testing: manual system + 2-client demo chat\n"
        "Negative tests: AI down, Zego unset, Storage rules missing\n"
        "Evaluation: prototype completeness — not fake SPSS/N stats\n"
        "Ready for structured UAT next",
    )

    set_slide_body(
        slides[15],
        "RESULTS AND DISCUSSION (1/4)",
        "Delivered working student app (unza_z_chat)\n"
        "Demo OTP → profile → peer chat verified\n"
        "Groups, status, communities, ZFeed operational\n"
        "[Screenshot: Home / Chats — PLACEHOLDER]",
    )

    set_slide_body(
        slides[16],
        "RESULTS AND DISCUSSION (2/4)",
        "Courses + past paper download/cache working\n"
        "Planner + local notifications path implemented\n"
        "Student classroom routes implemented\n"
        "[Screenshots: Courses / Papers / Planner — PLACEHOLDER]",
    )

    set_slide_body(
        slides[17],
        "RESULTS AND DISCUSSION (3/4)",
        "AI companion via Node + Claude when backend up\n"
        "Clear “AI requires backend” when offline\n"
        "Calls/live gated on Zego configuration\n"
        "[Screenshots: AI / ZFeed — PLACEHOLDER]",
    )

    set_slide_body(
        slides[18],
        "TEAM CONTRIBUTIONS (EQUAL THIRDS)",
        f"• {STUDENTS[0][0]} ({STUDENTS[0][1]}) — Coordinator; messaging, calls, communities\n"
        f"• {STUDENTS[1][0]} ({STUDENTS[1][1]}) — Courses, papers, planner, student classroom\n"
        f"• {STUDENTS[2][0]} ({STUDENTS[2][1]}) — Auth, AI/threads (ZFeed), deployment\n"
        "Shared: integration, testing, report & defence",
    )

    set_slide_body(
        slides[19],
        "CONCLUSION",
        "Student-stream UnZA Z CHAT prototype completed\n"
        "Objectives met for implementation; UAT still future work\n"
        "Honest config-gated AI/calls improved demo credibility\n"
        "Suitable baseline for departmental pilot discussions",
    )

    set_slide_body(
        slides[20],
        "RECOMMENDATIONS",
        "Run ethics-approved structured UAT with UNZA students\n"
        "Production: DEMO_AUTH=false + real OTP; deploy rules\n"
        "Publish AI academic-integrity guidelines\n"
        "Curate programme past-paper libraries\n"
        "Enable Zego only with credentials & capacity",
    )

    set_slide_body(
        slides[21],
        "REFERENCES",
        "Davis (1989) TAM — MIS Quarterly\n"
        "Flutter & Firebase documentation (Google)\n"
        "Anthropic Claude API docs\n"
        "ZegoCloud documentation\n"
        "UNZA DCI FYP Report Template 2026\n"
        "Full list in the Final Report",
    )

    prs.save(str(OUT_PPTX))
    print("Wrote", OUT_PPTX)


if __name__ == "__main__":
    build_report()
    build_defence()
