# Task 1: Contact Data Model

Create `lib/contact.ex` with a Contact struct that includes:

## Requirements
1. Define a Contact struct with fields:
   - id (UUID string, auto-generated)
   - name (required string)
   - email (required string)
   - phone (optional string)
   - notes (optional string)
   - inserted_at (DateTime, auto-generated)

2. Implement these functions:
   - `new/1` - Create a new contact from a map, generate id and timestamp
   - `valid_email?/1` - Validate email format (basic regex)
   - `valid_phone?/1` - Validate phone format (digits and dashes)
   - `to_map/1` - Convert contact struct to map for JSON serialization
   - `from_map/1` - Create contact struct from map (for deserialization)

3. Include @doc comments explaining each function

## Implementation Details
- Use UUID for ID generation (can use :crypto.strong_rand_bytes)
- Email regex: ~r/^[\w._%+-]+@[\w.-]+\.[a-zA-Z]{2,}$/
- Phone regex: ~r/^[\d\-\(\) ]+$/
- Use DateTime.utc_now() for timestamps

## Example Usage (in comments)
```elixir
# contact = Contact.new(%{name: "John Doe", email: "john@example.com", phone: "555-1234"})
# Contact.valid_email?("test@example.com") # => true
# map = Contact.to_map(contact)
# contact2 = Contact.from_map(map)
```

Output: Complete Elixir module code
