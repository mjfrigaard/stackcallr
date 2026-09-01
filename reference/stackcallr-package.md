# stackcallr: Statically Inspect and Visualize the Call Tree of a Function

Builds the call tree of a function from its source code, without running
it. Given a function name, the function's body is parsed to find every
function it calls, and those calls are followed recursively, resolving
'UseMethod()' dispatch into the registered S3 methods. The resulting
tree is printed as an indented outline.

## Author

**Maintainer**: Martin Frigaard <mjfrigaard@pm.me>

Authors:

- Martin Frigaard <mjfrigaard@pm.me>
