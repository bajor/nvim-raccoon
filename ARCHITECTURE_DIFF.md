# Architecture Diff

## Summary

Changed-file review comments now split by review target. Real diff lines still use GraphQL thread creation via `addPullRequestReview`, while lines outside GitHub's resolvable diff context fall back to REST file-level review comments using `subject_type=file`.

## Diagrams

```mermaid
graph TD
    A[comments.lua\nsend_new_thread] --> B{line in review context?}
    B -->|yes| C[api.lua\ncreate_review_thread]
    C --> D[GraphQL addPullRequestReview]
    D --> F[comments.lua\nnotify + sync]
    B -->|no| E[api.lua\ncreate_comment\nsubject_type=file]
    E --> F
```

```mermaid
sequenceDiagram
    participant U as User
    participant C as comments.lua
    participant A as api.lua
    participant G as GitHub GraphQL
    participant R as GitHub REST

    U->>C: Send new changed-file thread
    C->>C: Check diff-context eligibility
    alt Line is in review context
        C->>A: create_review_thread(path, line, body)
        A->>G: addPullRequestReview(...threads...)
        G-->>A: pullRequestReview { id }
        A-->>C: success
    else Line is outside diff context
        C->>A: create_comment(path, subject_type=file, body)
        A->>R: POST /pulls/{n}/comments
        R-->>A: file-level review comment
        A-->>C: success
    end
    C-->>U: "Thread sent" + sync
```

## Changes

### Added

- `tests/api_spec.lua`: regression coverage for both the GraphQL changed-line path and the REST file-comment fallback for changed files outside diff context.

### Modified

- `lua/raccoon/api.lua`: `create_review_thread` now selects `pullRequestReview { id }` from `addPullRequestReview`, and `create_comment` now supports REST file-level review comments with `subject_type=file`.
- `lua/raccoon/comments.lua`: changed-file lines outside diff context now bypass GraphQL line resolution and send as file-level REST comments instead.

### Removed

- Dependence on GraphQL line resolution for changed-file comments that are outside GitHub's diff context.
