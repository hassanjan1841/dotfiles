---
name: ui-libraries
description: Use a real component library instead of hand-building UI. Use when building or editing any frontend that needs a toast, drawer, bottom sheet, command menu, animated number, dialog, dropdown, select, tabs, popover, loading state, landing page effect, or AI chat UI (streaming text, approval cards, diff views). Also use when the UI looks like default shadcn or an "AI look".
---

# UI libraries, do not build from scratch

Hand-built toasts pile up, drawers do not drag, command menus break on keyboard. Use a library that already solved it.

## Rules

1. Before writing a toast, drawer, command menu, animated number, dialog, dropdown or tabs, pick a library from the tables below.
2. Read `package.json` first. If the project already has a library for the job, use it. Do not swap dependencies unasked.
3. Install through the library's CLI or registry so the code lands in the project and can be edited.
4. Restyle the foundation (radius, colors, type) so it does not look like default shadcn.
5. One standout effect per page, never several.
6. If the task is not covered here, say so and recommend from your own knowledge.

## 1. Foundations (behavior: keyboard, focus, a11y)

| Use | For |
| --- | --- |
| shadcn/ui (ui.shadcn.com) | Most of the app: buttons, inputs, dialogs, dropdowns, tabs |
| Base UI (base-ui.com) | Unstyled accessible primitives, you do the styling |
| Radix (radix-ui.com) | Unstyled primitives, what shadcn is built on |

- Install with the shadcn CLI, e.g. `shadcn add <component>` (use the project's local binary if present).
- Default shadcn is an AI look: same radius, same gray, same fonts.
- Change these three first, they carry the personality:
  - Radius: tighter or fully round, not the default.
  - Colors: the product's brand palette, not neutral gray.
  - Type: a distinct heading font (a serif heading reads as editorial, not SaaS).
- Ask the user for brand colors and fonts up front. shadcn copies code into the repo, so everything is editable.

## 2. Specialists (one component, done right)

| Task | Library | npm package |
| --- | --- | --- |
| Toasts (stacking, hover expand, enter/exit) | Sonner | `sonner` |
| Drawers (drag up from bottom, flick to close) | Vaul | `vaul` |
| Command menu (Cmd+K search) | cmdk | `cmdk` |
| Numbers that animate on change (price, balance) | NumberFlow | `@number-flow/react` |

- Sonner and Vaul are by Emil Kowalski.
- Emil also publishes a `pick-ui-library` skill (github.com/emilkowalski/skills). It only runs when invoked by name, so this skill covers the auto-trigger.
- If you catch yourself writing a custom toast system, stop and use Sonner.

## 3. Design components (finished, styled, copy into the project)

| Library | Best for |
| --- | --- |
| Beautiful UI (beautifului.dev) | AI products: streaming text, agent approval cards, diff views, agent screens |
| RareUI (rareui.in) | Flashy moments: animated buttons, text effects, interactive backgrounds |
| Magic UI (magicui.design) | 150+ free animated components, built to sit on top of shadcn |
| Aceternity UI (ui.aceternity.com) | Landing page effects: 3D cards, background beams, marquees |
| 21st.dev | Marketplace of community components, browse when you need one specific thing |

- Install with the library's own CLI, or the shadcn CLI where it supports it.
- Standout rule: one animated hero or one interactive background per page. Ten glowing, moving things and nothing stands out.

## Quick picks

| Need | Use |
| --- | --- |
| Toast | Sonner |
| Mobile drawer or sheet | Vaul |
| Cmd+K menu | cmdk |
| Count-up or changing number | NumberFlow |
| Dialog, dropdown, select, tabs | shadcn/ui (Base UI or Radix underneath) |
| AI chat, agent approval, diff view | Beautiful UI |
| Landing page hero effect | Aceternity UI or Magic UI, one only |
| Not sure, want options | Browse 21st.dev |

## After building

- Check the toast stacks, the drawer drags, the command menu works by keyboard alone.
- Check the radius, colors and type were changed from shadcn defaults.
- Count the animated showpieces on each page: it must be one.
