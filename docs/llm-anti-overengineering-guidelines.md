# LLM Anti-Over-Engineering Guidelines

## CRITICAL DIRECTIVE: Read This Before Any Implementation

You are about to work on code integration tasks. This document contains critical patterns to AVOID based on previous failures. **Apply these checks rigorously**.

---

## 🚨 IMMEDIATE STOP CONDITIONS

**BEFORE WRITING ANY CODE, if you detect these patterns, STOP and reconsider:**

### RED FLAG #1: Building Management on Top of Management
```
❌ WRONG: "I'll build a service to manage X registration"
✅ RIGHT: "How does X's built-in manager work?"
```

### RED FLAG #2: Abstraction Over Integration
```
❌ WRONG: "I'll create an interface to wrap the existing system"
✅ RIGHT: "How does the existing system want me to integrate?"
```

### RED FLAG #3: Infrastructure for Infrastructure
```
❌ WRONG: "I'll build tooling to help with integration"
✅ RIGHT: "What's the simplest way to just integrate?"
```

---

## 🎯 MANDATORY DECISION FRAMEWORK

### Step 1: Discovery-to-Deletion Check
**After learning how any existing system works:**
1. List what you planned to build
2. Cross out everything the existing system handles
3. If >50% crossed out → DELETE your approach, use the existing system

### Step 2: The "Delegation Forcing Function"
**Before implementing anything, complete this sentence:**
"I am building this because the existing system cannot _______________"

**If you cannot complete this sentence with a specific technical limitation, STOP. Use the existing system.**

### Step 3: The User Goal Reality Check
**Every 15 minutes, write:**
- User wants: _______________
- I'm building: _______________  
- This serves the user by: _______________

**If #3 mentions "infrastructure", "management", "integration", or "service" → RED FLAG**

---

## 🧠 COGNITIVE TRAP DETECTION

### Trap: "Sophisticated = Better"
**Symptom**: Proud of architectural complexity
**Antidote**: Count lines of code. Fewer = better.

### Trap: "I Need to Manage This"
**Symptom**: Building management classes/services
**Antidote**: Prove the existing system can't manage it

### Trap: "This Needs Configuration"
**Symptom**: Adding config detection, merging, defaults
**Antidote**: Use the existing system's defaults

### Trap: "I Should Make This Generic"
**Symptom**: Building frameworks for future use
**Antidote**: Solve only the immediate specific problem

---

## ⚡ FORCED SIMPLIFICATION TECHNIQUES

### Technique 1: The 30-Line Rule
**No new file >30 lines without proving complexity is unavoidable**

### Technique 2: The "Junior Developer Test"
**Explain your approach to an imaginary junior developer in 2 sentences**
- If they would look confused → too complex
- If they would ask "why not just..." → listen to that

### Technique 3: The Deletion Practice
**After writing any code, spend 10 minutes trying to delete it entirely**
- What simpler thing could replace this?
- What existing system could handle this?

---

## 🔍 INTEGRATION-SPECIFIC GUIDELINES

### When Working with Existing Systems (Neo-tree, nui, etc.):

#### ALWAYS Ask First:
1. "What does this system want from me?" (not "How do I make this system work?")
2. "What's the path of least resistance?"
3. "What examples exist of simple integration?"

#### NEVER Do:
- Build abstractions over the system's APIs
- Create "smart" wrappers or managers
- Add configuration layers the system doesn't require
- Build registration/setup logic if the system handles it

#### Example Pattern Recognition:
```lua
-- ❌ WRONG: Building on top of existing management
local MyManager = {}
function MyManager:setup()
  -- Complex logic to "help" with existing system
end

-- ✅ RIGHT: Direct integration with existing system
local MySource = {}
MySource.get_items = function() -- System expects this method
  -- Just provide data, let system handle everything else
end
```

---

## 🎪 TESTING ANTI-PATTERNS

### WRONG: Testing Infrastructure
```lua
-- ❌ Testing that your registration service works
assert(my_manager:isRegistered())
```

### RIGHT: Testing User Goals
```lua
-- ✅ Testing that user can do what they want
user_expands_variable()
assert(shows_child_properties())
```

### WRONG: Surface-Level Success
```lua
-- ❌ Window appears = success
assert(window_is_visible())
```

### RIGHT: Functional Success
```lua
-- ✅ Core functionality works = success
assert(can_navigate_object_tree())
```

---

## 🔧 IMPLEMENTATION CHECKLIST

**Before considering any task complete:**

- [ ] User can accomplish their stated goal
- [ ] I used existing systems instead of building around them
- [ ] My code is primarily data transformation, not management
- [ ] I can explain the solution in <2 sentences without jargon
- [ ] Deleting my code would force me to rebuild core functionality (not just infrastructure)

---

## 🚫 BANNED PHRASES IN IMPLEMENTATION

**If you catch yourself saying/thinking:**
- "I'll build a service to..."
- "I need to manage..."
- "I'll create an interface for..."
- "I'll add configuration to..."
- "I'll make this more robust by..."

**STOP. Ask instead:**
- "What existing system handles this?"
- "What's the simplest possible version?"
- "How do I just provide data/functionality directly?"

---

## 🎯 SUCCESS DEFINITION

**Your implementation is successful when:**
1. **User goal achieved**: User can do what they wanted
2. **Minimal footprint**: <50 lines of actual new logic
3. **Direct integration**: No abstraction layers over existing systems
4. **Obvious simplicity**: A junior developer would think "of course, that's how you'd do it"

**Your implementation is FAILED when:**
- Tests pass but user goal unmet
- You built impressive architecture but missed core functionality  
- You created management for things already managed
- You added complexity instead of using existing capabilities

---

## 🧪 BEFORE-CODING RITUAL

**Complete this checklist every time:**

1. **What existing system am I integrating with?**
2. **How does that system want integrations to work?**
3. **What's the simplest example of integration with that system?**
4. **What would I build if I had only 30 lines of code?**
5. **What management/infrastructure am I tempted to build that I can avoid?**

**Only proceed if you can answer all 5 questions and #4 achieves the user goal.**

---

*Remember: The best code is often the code you don't write because you found a way to delegate to existing systems instead.*