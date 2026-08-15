# Project instructions

## Interface content

When you create or revise user-facing interfaces:

- Design self-explanatory, low-noise interfaces. Use labels, grouping, state,
  and affordances to communicate common actions without supporting paragraphs.
- Remove persistent text that repeats control labels, narrates normal behavior,
  advertises capabilities, or explains implementation details.
- Use concise, specific action labels.
- Apply progressive disclosure. Place advanced explanations in contextual help,
  expandable sections, confirmation dialogs, or documentation.
- Show guidance only when it prevents a likely mistake, explains a non-obvious
  constraint, identifies a prerequisite, or supports an irreversible action.
- Place guidance beside the control or state that requires it.
- Make errors and status messages actionable and temporary where possible.
- Prefer one short sentence when inline guidance remains necessary. If the
  explanation requires a paragraph, first consider redesigning the interface.
- Do not explain through prose what the interface can communicate through
  structure, labels, disabled states, selection, or feedback.
- Make the primary workflow understandable by scanning the interface without
  reading body copy.

## Technical documentation style

When you create or revise technical documentation:

- Follow the Google Developer Documentation Style Guide.
- Prefer E-Prime when it improves clarity and directness.
- Allow a natural copular sentence when an E-Prime rewrite would weaken a
  definition, obscure a state or identity, add ambiguity, or inflate the text.
- Match the document's purpose, audience, and established tone.
- Address the reader directly and use imperative sentences for instructions,
  procedures, prerequisites, and direct guidance.
- Use concise active declarative sentences for concepts, architecture,
  reference material, and observed behavior.
- Begin instructions with strong action verbs.
- Prefer the smallest accurate change during a style-only sweep.
- Preserve evidence qualifiers, uncertainty, technical nuance, and information
  density.
- Do not turn factual descriptions or observations into commands or
  requirements.
- Preserve exact code, commands, identifiers, API names, UI labels, quotations,
  logs, and error messages.
- Preserve technical accuracy when rewriting sentences.
- Before finalizing documentation, scan authored prose for `am`, `is`, `are`,
  `was`, `were`, `be`, `being`, and `been`. Review each match and rewrite it
  only when the change improves clarity without changing meaning or tone.
