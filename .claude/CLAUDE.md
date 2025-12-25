## Code Design Principles

- When adding logic around library calls, first consider whether it would be better to enhance the library itself rather than adding wrapper logic in the client code.
- Prefer pushing complexity into well-tested, reusable library code over ad-hoc client-side handling.

- always be careful to review, abstract common logic. 
- search for existing logic before duplicating and avoid code duplication
- always try to think of a few ways to implement and compare pros and cons before deciding
- always consider maintainability, testability, readability and possible future extensions