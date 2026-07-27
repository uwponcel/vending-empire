# Product

## Register

product

## Users

Roblox simulator players joining a shared server for a short, immediately understandable
progression loop. New players need to buy, collect, and reinvest without instructions, while
returning players need to read their plot and next useful action at a glance.

## Product Purpose

Vending Empire turns a personal plot into a visible production business. Players place
machines, walk up to collect their earnings, and reinvest in more capable machines. Success
means the first loop is obvious within a minute, progression choices remain legible, and other
players' plots create aspiration without obscuring the local player's task.

## Brand Personality

Approachable, industrious, and crisp. Feedback should feel rewarding without becoming noisy,
and the interface should feel like part of the game rather than a separate dashboard.

## Anti-references

Avoid saturated gradients, stacked popups, constant particle noise, and dense shop screens that
hide the world. Avoid visual effects that make neighbouring plots harder to compare.

Two earlier entries here were removed deliberately, not by drift. "Buttons competing for
attention" and "decorative motion without state meaning" ruled out the genre's own launcher
idiom: a large icon-only button that bounces occasionally to pull the eye. That idiom is now
wanted, because the reference games that hold players use it and because a launcher a new player
never notices is worse than one that nudges. What replaces the blanket ban is a budget:

- Attention motion belongs on **launchers only**, never on a value the player is reading.
- It plays on an interval, jittered per button, and never while that button is hovered, pressed,
  or already open.
- It is skipped entirely under `GuiService.ReducedMotionEnabled`.
- One launcher column, bottom left. Anything that wants attention competes for a slot in it
  rather than adding a new floating button somewhere else.

## Design Principles

1. Make the next action obvious without a tutorial wall.
2. Keep authority invisible: show immediate feedback while the server remains the source of truth.
3. Reward the core loop with concise sound, motion, and number feedback.
4. Preserve the world view so the player's plot and neighbours remain the main visual surface.
5. Use category and state consistently so players learn the interface once.

## Accessibility & Inclusion

Do not encode category, affordability, or success by colour alone. Keep text readable at Roblox
UI scale, support keyboard and gamepad affordances, avoid rapid flashes, and make non-essential
motion safe to omit when reduced-motion preferences are available.
