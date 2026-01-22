# ExDoc Documentation Search

Search the local ExDoc documentation for accurate module and function information.

## Usage

Invoke this command when you need to:
- Look up exact function signatures and typespecs
- Verify module documentation before writing README
- Understand existing API before modifying code
- Check if a function/module exists

## Instructions

When this command is invoked with a search term (e.g., `/docs Permission` or `/docs check evaluate`):

1. **Check if docs are fresh**:
   - Compare `doc/.build` timestamp with latest `lib/**/*.ex` modification
   - If any source file is newer than docs, run `mix docs` first

2. **Search the documentation**:
   - Search `doc/*.html` files for the given term
   - Use grep to find relevant content
   - Extract module names, function signatures, and descriptions

3. **Return structured results**:
   - Module name and file path
   - Function signatures (def/defp)
   - @doc content
   - @spec if available
   - Related modules

## Example Search Commands

```bash
# Check if docs need regeneration
DOC_BUILD="doc/.build"
LATEST_SOURCE=$(find lib -name "*.ex" -newer "$DOC_BUILD" 2>/dev/null | head -1)

if [ -n "$LATEST_SOURCE" ] || [ ! -f "$DOC_BUILD" ]; then
  echo "Docs outdated, regenerating..."
  mix docs
fi

# Search for the term
SEARCH_TERM="$ARGUMENTS"
grep -ril "$SEARCH_TERM" doc/*.html | while read file; do
  echo "=== $file ==="
  grep -i "$SEARCH_TERM" "$file" | sed 's/<[^>]*>//g' | head -20
done
```

## Output Format

Return results in this format:
```
Module: AshGrant.Permission
File: doc/AshGrant.Permission.html

Functions:
- parse(string) :: {:ok, Permission.t()} | {:error, String.t()}
- parse!(string) :: Permission.t()
- matches?(permission, resource, action) :: boolean()

Description:
Permission struct with parsing and matching capabilities...
```
