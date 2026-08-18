---
# Design System: VivaceGraph Embeddings
# Canonical token format for developer-facing interfaces (REST, REPL, tutorials, logs)
# All tokens referenced by name in ux-spec.md and implementation

colors:
  # Brand
  brand-primary: "#2D5EAA"      # VivaceGraph blue — primary actions, links, active states
  brand-primary-hover: "#1E4A8C"
  brand-primary-light: "#E8F0FA"  # backgrounds, badges
  brand-secondary: "#6B7280"    # muted text, secondary actions
  brand-accent: "#E07C00"       # warnings, index build progress

  # Semantic
  success: "#059669"            # commit success, recall ≥ target
  success-light: "#ECFDF5"
  warning: "#D97706"            # recall below target, deprecated API
  warning-light: "#FFFBEB"
  error: "#DC2626"              # transaction abort, dim mismatch, crash
  error-light: "#FEF2F2"
  info: "#0284C7"               # ingest progress, query latency

  # Neutral (grayscale for code/terminal)
  neutral-900: "#111827"        # primary text, REPL prompt
  neutral-700: "#374151"        # secondary text, log timestamps
  neutral-500: "#6B7280"        # comments, disabled, placeholders
  neutral-300: "#D1D5DB"        # borders, separators
  neutral-100: "#F3F4F6"        # code block backgrounds
  neutral-50: "#F9FAFB"         # page backgrounds
  white: "#FFFFFF"

  # Syntax highlighting (for tutorial output, REPL pretty-print)
  syntax-keyword: "#7C3AED"     # def-vertex, with-transaction, select
  syntax-function: "#2563EB"    # make-document, knn, hnsw-knn-search
  syntax-string: "#16A34A"      # "title", "cosine"
  syntax-number: "#EA580C"      # 384, 10, 0.042
  syntax-comment: "#9CA3AF"     # ; comments
  syntax-type: "#7C2D12"        # :vector, :single-float, :hnsw
  syntax-variable: "#BE185D"    # ?doc, ?dist, qvec

  # Terminal/REPL specific
  repl-prompt: "#2D5EAA"        # CL-USER>
  repl-output: "#374151"        # returned values
  repl-error: "#DC2626"         # debugger, backtrace

typography:
  # Monospace for code, REPL, logs, JSON
  font-mono:
    family: "JetBrains Mono, Fira Code, SF Mono, Menlo, Consolas, monospace"
    size-base: "13px"
    line-height: 1.6
    weight-regular: 400
    weight-medium: 500
    weight-bold: 700

  # UI text (REST docs, error messages, tutorial prose)
  font-ui:
    family: "Inter, system-ui, -apple-system, sans-serif"
    size-base: "14px"
    line-height: 1.5
    weight-regular: 400
    weight-medium: 500
    weight-semibold: 600
    weight-bold: 700

  # Headings (README, tutorial markdown, API docs)
  heading:
    h1: { size: "28px", weight: 700, line-height: 1.3, letter-spacing: "-0.02em" }
    h2: { size: "22px", weight: 600, line-height: 1.3, letter-spacing: "-0.01em" }
    h3: { size: "18px", weight: 600, line-height: 1.4 }
    h4: { size: "15px", weight: 600, line-height: 1.4 }

  # Scale for code blocks
  code-scale:
    sm: "11px"   # inline code in prose
    base: "13px" # code blocks, REPL
    lg: "15px"   # tutorial terminals

spacing:
  # Base unit: 4px
  unit: 4
  scale:
    0: 0
    1: 4   # tight: icon-text, badge gaps
    2: 8   # compact: form field gaps, list item padding
    3: 12  # default: component padding, card gaps
    4: 16  # comfortable: section gaps, card padding
    5: 24  # loose: major section breaks
    6: 32  # page margins
    8: 48  # hero/topic separation
    10: 64 # major layout regions

  # Specific semantic spacings
  repl-line-gap: 8        # between REPL expressions
  log-entry-gap: 4        # between log lines
  json-indent: 2          # pretty-print JSON
  code-block-padding: 16  # code block internal padding
  table-cell-padding: "8px 12px"  # markdown tables

border:
  radius:
    none: 0
    sm: 4      # badges, inline code
    md: 8      # cards, code blocks, inputs
    lg: 12     # modals, dropdowns
    full: 9999 # pills, badges
  width:
    thin: 1    # default borders
    thick: 2   # focus rings, active states
  color:
    default: "#D1D5DB"  # neutral-300
    focus: "#2D5EAA"    # brand-primary
    error: "#DC2626"    # error

shadow:
  none: "none"
  sm: "0 1px 2px 0 rgb(0 0 0 / 0.05)"      # cards, code blocks
  md: "0 4px 6px -1px rgb(0 0 0 / 0.1)"    # dropdowns, tooltips
  lg: "0 10px 15px -3px rgb(0 0 0 / 0.1)"  # modals
  focus: "0 0 0 3px #E8F0FA"               # brand-primary-light ring

motion:
  duration:
    instant: "0ms"
    fast: "100ms"    # hover, focus
    normal: "200ms"  # transitions, expand/collapse
    slow: "300ms"    # modals, drawers
  easing:
    default: "cubic-bezier(0.4, 0, 0.2, 1)"  # standard
    emphasize: "cubic-bezier(0.05, 0.7, 0.1, 1.0)" # enter animations
    decelerate: "cubic-bezier(0, 0, 0.2, 1)" # exit animations

# Component tokens (composed from primitives)
components:
  # REPL / Terminal
  repl:
    prompt:
      color: "{colors.repl-prompt}"
      font: "{typography.font-mono}"
      size: "{typography.font-mono.size-base}"
    output:
      color: "{colors.repl-output}"
      font: "{typography.font-mono}"
    error:
      color: "{colors.repl-error}"
      font: "{typography.font-mono}"

  # Code blocks (tutorials, docs, REST examples)
  code-block:
    background: "{colors.neutral-100}"
    border-radius: "{border.radius.md}"
    padding: "{spacing.code-block-padding}"
    font: "{typography.font-mono}"
    size: "{typography.code-scale.base}"
    line-height: "{typography.font-mono.line-height}"
    overflow: "auto"

  # Badges (status, metrics)
  badge:
    padding: "2px 8px"
    border-radius: "{border.radius.full}"
    font: "{typography.font-ui}"
    size: "11px"
    weight: 500
    variants:
      success:
        bg: "{colors.success-light}"
        color: "{colors.success}"
      warning:
        bg: "{colors.warning-light}"
        color: "{colors.warning}"
      error:
        bg: "{colors.error-light}"
        color: "{colors.error}"
      info:
        bg: "{colors.brand-primary-light}"
        color: "{colors.brand-primary}"
      neutral:
        bg: "{colors.neutral-100}"
        color: "{colors.neutral-700}"

  # Buttons (REST API docs, tutorial actions)
  button:
    font: "{typography.font-ui}"
    size: "{typography.font-ui.size-base}"
    weight: 500
    border-radius: "{border.radius.md}"
    padding: "8px 16px"
    transition: "background {motion.duration.fast} {motion.easing.default}"
    variants:
      primary:
        bg: "{colors.brand-primary}"
        color: "{colors.white}"
        hover: "{colors.brand-primary-hover}"
        focus-ring: "{shadow.focus}"
      secondary:
        bg: "{colors.neutral-100}"
        color: "{colors.neutral-900}"
        hover: "{colors.neutral-300}"
        focus-ring: "{shadow.focus}"
      ghost:
        bg: "transparent"
        color: "{colors.brand-primary}"
        hover: "{colors.brand-primary-light}"
        focus-ring: "{shadow.focus}"

  # Inputs (REST API docs, config forms)
  input:
    font: "{typography.font-mono}"
    size: "{typography.font-mono.size-base}"
    padding: "8px 12px"
    border: "{border.width.thin} solid {colors.neutral-300}"
    border-radius: "{border.radius.md}"
    background: "{colors.white}"
    color: "{colors.neutral-900}"
    placeholder: "{colors.neutral-500}"
    focus:
      border-color: "{colors.brand-primary}"
      box-shadow: "{shadow.focus}"
    error:
      border-color: "{colors.error}"
      focus-box-shadow: "0 0 0 3px {colors.error-light}"

  # Tables (markdown, admin endpoints)
  table:
    border-collapse: "collapse"
    width: "100%"
    font: "{typography.font-ui}"
    size: "{typography.font-ui.size-base}"
    th:
      background: "{colors.neutral-50}"
      color: "{colors.neutral-700}"
      weight: 600
      padding: "{spacing.table-cell-padding}"
      border-bottom: "2px solid {colors.neutral-300}"
      text-align: "left"
    td:
      padding: "{spacing.table-cell-padding}"
      border-bottom: "1px solid {colors.neutral-300}"
      color: "{colors.neutral-900}"
    tr:
      hover-background: "{colors.neutral-50}"

  # Cards (tutorial steps, metric summaries)
  card:
    background: "{colors.white}"
    border: "{border.width.thin} solid {colors.neutral-300}"
    border-radius: "{border.radius.lg}"
    padding: "{spacing[4]}"
    shadow: "{shadow.sm}"

  # Alerts (error states, warnings in tutorials)
  alert:
    padding: "{spacing[3]} {spacing[4]}"
    border-radius: "{border.radius.md}"
    border: "{border.width.thin} solid"
    font: "{typography.font-ui}"
    size: "{typography.font-ui.size-base}"
    variants:
      success:
        bg: "{colors.success-light}"
        border-color: "{colors.success}"
        color: "{colors.success}"
      warning:
        bg: "{colors.warning-light}"
        border-color: "{colors.warning}"
        color: "{colors.warning}"
      error:
        bg: "{colors.error-light}"
        border-color: "{colors.error}"
        color: "{colors.error}"
      info:
        bg: "{colors.brand-primary-light}"
        border-color: "{colors.brand-primary}"
        color: "{colors.brand-primary}"

  # Log entries (structured logging)
  log-entry:
    font: "{typography.font-mono}"
    size: "12px"
    line-height: 1.5
    padding: "2px 0"
    timestamp:
      color: "{colors.neutral-500}"
    level:
      debug: "{colors.neutral-500}"
      info: "{colors.info}"
      warn: "{colors.warning}"
      error: "{colors.error}"
    message:
      color: "{colors.neutral-900}"
    key-value:
      key: "{colors.neutral-700}"
      value: "{colors.neutral-900}"

# Breakpoints (for responsive REST docs, tutorial pages)
breakpoints:
  sm: "640px"   # mobile
  md: "768px"   # tablet
  lg: "1024px"  # desktop
  xl: "1280px"  # wide
  2xl: "1536px" # ultra-wide

# Z-index scale
z-index:
  base: 0
  dropdown: 100
  sticky: 200
  modal: 300
  popover: 400
  toast: 500
  tooltip: 600

# Icon sizes (for REST docs, tutorial UI)
icon:
  sm: "14px"
  md: "18px"
  lg: "24px"

# Focus visible outline (accessibility)
focus-visible:
  outline: "2px solid {colors.brand-primary}"
  outline-offset: "2px"
  border-radius: "{border.radius.sm}"

# Reduced motion
reduced-motion:
  duration: "0.01ms"
  transition: "none"

# Print styles (for tutorial PDF export)
print:
  code-block:
    background: "{colors.white}"
    border: "1px solid {colors.neutral-300}"
    page-break-inside: "avoid"
  colors:
    - all semantic colors map to grayscale equivalents
  shadows: none