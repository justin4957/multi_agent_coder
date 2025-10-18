# Task 4: CLI Interface Module

Create `lib/cli.ex` with interactive command-line interface.

## Requirements
1. Create ContactManager.CLI module with:
   - `run/0` - Main entry point, starts interactive loop
   - `show_menu/0` - Display available commands
   - `handle_command/1` - Process user input commands
   - `format_contact/1` - Pretty-print a contact
   - `format_contact_list/1` - Pretty-print list of contacts

2. Supported commands:
   - "add" - Prompt for contact details, add to database
   - "search" - Search by name or email
   - "list" - Show all contacts
   - "delete" - Delete contact by ID
   - "export" - Export to JSON file
   - "help" - Show command help
   - "quit" - Exit program

3. User experience:
   - Clear prompts for input
   - Colorful output (use IO.ANSI)
   - Display success/error messages
   - Show contact count

## Implementation Details
- Use IO.gets/1 for reading input
- Use String.trim to clean input
- Use ContactManager API for all operations
- Format with borders and spacing for readability
- Colors: green for success, red for errors, cyan for prompts

## Example Output (in comments)
```
=== Contact Manager ===
Commands: add, search, list, delete, export, help, quit

> add
Name: John Doe
Email: john@example.com
Phone: 555-1234
Notes: Marketing contact

✓ Contact added successfully!

> list
=== All Contacts (1) ===
[1] John Doe <john@example.com>
    Phone: 555-1234
    Notes: Marketing contact
```

Output: Complete Elixir CLI module with interactive loop
