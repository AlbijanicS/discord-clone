# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

Primary users are the project owner's work colleagues and people reviewing the project as a portfolio piece. They evaluate and use a private-alpha, Discord-like collaboration application.

## Product Purpose

Discord Clone is a private-alpha collaboration application and a learning project for Phoenix, LiveView, Ecto, PostgreSQL, and OTP. It lets authenticated users organize workspaces, communicate in channels and direct conversations, manage friendships and activity, and participate in real-time voice channels. Success means delivering a credible, demonstrable collaboration experience while showing the project's real-time systems and architectural depth.

## Positioning

The product deliberately combines a Discord-like collaboration model with a transparent learning-project mandate: its real-time collaboration features, including browser voice channels, are implemented as a Phoenix/LiveView and OTP system rather than presented as a generic static portfolio mockup.

## Operating Context

Users sign in to a private-alpha web app, enter workspaces, navigate a familiar Discord-like destination and channel hierarchy, exchange messages, use direct conversations and friend workflows, review activity, and join voice channels. The project is evaluated both as a working collaboration product and as a portfolio demonstration.

## Capabilities and Constraints

- Authenticated users can create and join workspaces, use workspace channels, send and receive real-time messages, manage friends and direct conversations, and view activity.
- Voice channels provide real-time browser audio with participant state and controls.
- The existing Discord-like information architecture, LiveView behavior, voice-channel functionality, and backend/API contracts must be preserved.
- Visual design may change freely, but product behavior must not.
- The product is currently a private alpha, not a public self-service service.

## Brand Commitments

Use the existing Discord-like interaction model and vocabulary where it reflects product behavior. Visual styling is intentionally not a binding brand constraint.

## Evidence on Hand

- Working Phoenix application source, LiveViews, JavaScript voice hooks, and automated tests are present in this repository.
- `README.md` documents local development and the private-alpha deployment topology.
- `CONTEXT.md` defines the collaboration domain vocabulary and behavioral rules.
- No approved customer testimonials, public benchmarks, pricing, or brand asset system is on hand; future work must not invent them.

## Product Principles

- Preserve real collaboration behavior while improving presentation.
- Keep the familiar Discord-like hierarchy understandable to first-time reviewers.
- Make real-time and voice capabilities credible through usable, working flows.
- Treat private-alpha boundaries and existing contracts as product constraints.
- Let the implementation's technical substance support the portfolio story without substituting mock behavior.
