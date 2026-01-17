# Compliance Test Specification

This document defines the minimum set of test specifications to verify an implementation against the neograph-native SPEC using **n-wise orthogonal array testing**.

## Methodology

### N-Wise Testing Approach

N-wise (combinatorial) testing ensures that every n-tuple of parameter values is covered at least once. This minimizes test count while maximizing coverage of factor interactions.

- **2-wise (pairwise)**: Every pair of factor values appears together at least once
- **3-wise**: Every triple appears together (used for critical subsystems)

### Factor Extraction Strategy

1. Identify independent **subsystems** from the spec
2. Extract **factors** (dimensions) within each subsystem
3. Define **levels** (possible values) for each factor
4. Identify **cross-subsystem interactions** that require coverage
5. Generate minimal **covering arrays** for test combinations

---

## Factor Analysis

### Subsystem 1: Node/Property (NP)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| NP.1 Operation | insert, get, update, delete | CRUD completeness |
| NP.2 Property Type | nil, boolean, number, string | All supported types |
| NP.3 Node Existence | exists, not_exists | Boundary behavior |
| NP.4 Property Defined | yes, no | Nil vs undefined |

### Subsystem 2: Signal (SG)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| SG.1 Method | get, set, use | All Signal operations |
| SG.2 Value Type | nil, boolean, number, string | Type preservation |
| SG.3 Subscriber Count | 0, 1, many | Fan-out behavior |
| SG.4 Cleanup Returned | yes, no | Lifecycle management |
| SG.5 Unsub Timing | before_change, after_change, never | Cleanup triggers |

### Subsystem 3: EdgeHandle (EH)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| EH.1 Operation | link, unlink, iter, count, filter, each | All EdgeHandle methods |
| EH.2 Edge Cardinality | 0, 1, many | Empty/single/multiple |
| EH.3 Has Reverse | yes, no | Bidirectional tracking |
| EH.4 Subscription | none, onLink, onUnlink, each | Event types |
| EH.5 Filter Config | none, equality, range, compound | Filter complexity |

### Subsystem 4: Rollup (RL)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| RL.1 Kind | property, reference, collection | Three rollup types |
| RL.2 Compute | count, sum, avg, min, max, first, last, any, all | Property rollup operations |
| RL.3 Has Filters | yes, no | Filtered vs unfiltered |
| RL.4 Has Sort | yes, no | Sorted vs unsorted |
| RL.5 Target Count | 0, 1, many | Empty edge handling |
| RL.6 Trigger | edge_link, edge_unlink, target_prop_change | Update triggers |

### Subsystem 5: Index (IX)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| IX.1 Field Count | 1, 2+ | Single vs compound |
| IX.2 Direction | asc, desc, mixed | Sort ordering |
| IX.3 Filter Coverage | none, partial, full | Index selection |
| IX.4 Has Range Filter | yes, no | Range optimization |
| IX.5 Sort Matches | yes, no | Output ordering |

### Subsystem 6: View (VW)

| Factor | Levels | Rationale |
|--------|--------|-----------|
| VW.1 Root Filter | none, equality, range | Query complexity |
| VW.2 Expansion Depth | 0 (root), 1, 2+ (nested) | Deep tree support |
| VW.3 Pagination | start, middle, end | Viewport positioning |
| VW.4 Edge Config | default, eager, inline | Expansion behavior |
| VW.5 DAG Structure | tree, multi_parent | Multi-path nodes |
| VW.6 Callback | on_enter, on_leave, on_change | Event types |
| VW.7 Trigger | initial, runtime_change, collapse, delete | Event timing |

---

## Cross-Subsystem Interactions

These factor combinations span subsystems and require explicit coverage:

| Interaction | Factors | Rationale |
|-------------|---------|-----------|
| I1: Signal-on-Rollup | SG.1 × RL.1 | Rollups expose Signal interface |
| I2: Edge-triggers-Rollup | EH.1 × RL.6 | Link/unlink updates rollups |
| I3: Rollup-in-Index | RL.1=property × IX.1 | Property rollups are indexable |
| I4: View-uses-Index | VW.1 × IX.3 | Index coverage affects queries |
| I5: View-deep-Callback | VW.2 × VW.6 × VW.7 | Deep reactivity behavior |
| I6: DAG-multi-Callback | VW.5=multi × VW.6 | Per-path callback firing |

---

## Test Specifications

### Section 1: Node/Property Tests (NP-*)

#### 2-Wise Covering Array for NP Factors

```
| Test | NP.1       | NP.2    | NP.3       | NP.4 |
|------|------------|---------|------------|------|
| NP01 | insert     | string  | not_exists | yes  |
| NP02 | insert     | number  | not_exists | no   |
| NP03 | insert     | boolean | not_exists | yes  |
| NP04 | insert     | nil     | not_exists | no   |
| NP05 | get        | string  | exists     | yes  |
| NP06 | get        | number  | not_exists | yes  |
| NP07 | update     | string  | exists     | yes  |
| NP08 | update     | number  | exists     | no   |
| NP09 | update     | nil     | exists     | yes  |
| NP10 | delete     | string  | exists     | yes  |
| NP11 | delete     | number  | not_exists | no   |
```

#### NP01: Insert node with string property
- **Setup**: Empty graph with schema defining type "User" with string property "name"
- **Action**: `graph:insert("User", { name = "Alice" })`
- **Assert**: Returns node proxy; `node.name:get() == "Alice"`; `node._id` is positive integer; `node._type == "User"`
- **Spec Ref**: Graph Methods > CRUD, Node Proxy API

#### NP02: Insert node with number property, undefined optional
- **Setup**: Schema with optional property "age"
- **Action**: `graph:insert("User", { age = 30 })`
- **Assert**: `node.age:get() == 30`; accessing undefined property returns nil Signal
- **Spec Ref**: Property Values, Signal

#### NP03: Insert node with boolean property
- **Setup**: Schema with boolean property "active"
- **Action**: `graph:insert("User", { active = true })`
- **Assert**: `node.active:get() == true`
- **Spec Ref**: Property Values

#### NP04: Insert node with nil property value
- **Setup**: Schema with property "nickname"
- **Action**: `graph:insert("User", { nickname = nil })`
- **Assert**: `node.nickname:get() == nil`
- **Spec Ref**: Property Values

#### NP05: Get existing node by ID
- **Setup**: Node inserted with ID 1
- **Action**: `graph:get(1)`
- **Assert**: Returns same node proxy; properties accessible
- **Spec Ref**: Graph Methods > CRUD

#### NP06: Get non-existent node
- **Setup**: Empty graph
- **Action**: `graph:get(999)`
- **Assert**: Returns nil
- **Spec Ref**: Graph Methods > CRUD

#### NP07: Update existing node property
- **Setup**: Node with `name = "Alice"`
- **Action**: `graph:update(node._id, { name = "Bob" })`
- **Assert**: `node.name:get() == "Bob"`; returns updated node
- **Spec Ref**: Graph Methods > CRUD

#### NP08: Update adds undefined property
- **Setup**: Node without "age" property
- **Action**: `graph:update(node._id, { age = 25 })`
- **Assert**: `node.age:get() == 25`
- **Spec Ref**: Graph Methods > CRUD

#### NP09: Update property to nil using neo.NIL
- **Setup**: Node with `name = "Alice"`
- **Action**: `graph:update(node._id, { name = neo.NIL })`
- **Assert**: `node.name:get() == nil`
- **Note**: Use `neo.NIL` sentinel since Lua's `nil` cannot be passed in tables
- **Spec Ref**: Property Values

#### NP10: Delete existing node
- **Setup**: Node with ID 1
- **Action**: `graph:delete(1)`
- **Assert**: Returns true; `graph:get(1)` returns nil
- **Spec Ref**: Graph Methods > CRUD

#### NP11: Delete non-existent node
- **Setup**: Empty graph
- **Action**: `graph:delete(999)`
- **Assert**: Returns false (or nil)
- **Spec Ref**: Graph Methods > CRUD

---

### Section 2: Signal Tests (SG-*)

#### 2-Wise Covering Array for SG Factors

```
| Test | SG.1 | SG.2    | SG.3 | SG.4 | SG.5         |
|------|------|---------|------|------|--------------|
| SG01 | get  | string  | 0    | -    | -            |
| SG02 | get  | nil     | 0    | -    | -            |
| SG03 | set  | string  | 0    | -    | -            |
| SG04 | set  | number  | 1    | -    | -            |
| SG05 | set  | boolean | many | -    | -            |
| SG06 | use  | string  | 1    | no   | never        |
| SG07 | use  | number  | 1    | yes  | after_change |
| SG08 | use  | string  | many | yes  | before_change|
| SG09 | use  | nil     | 1    | yes  | never        |
```

#### SG01: Get returns current string value
- **Setup**: Node with `name = "Alice"`
- **Action**: `node.name:get()`
- **Assert**: Returns `"Alice"`
- **Spec Ref**: Signal > get()

#### SG02: Get returns nil for nil/undefined
- **Setup**: Node without property set
- **Action**: `node.optional_field:get()`
- **Assert**: Returns `nil`
- **Spec Ref**: Signal > get()

#### SG03: Set updates value
- **Setup**: Node with `name = "Alice"`
- **Action**: `node.name:set("Bob")`
- **Assert**: `node.name:get() == "Bob"`
- **Spec Ref**: Signal > set()

#### SG04: Set triggers single subscriber
- **Setup**: Node with subscriber via `use()`
- **Action**: `node.age:set(30)`
- **Assert**: Subscriber callback invoked with new value
- **Spec Ref**: Signal > set(), use()

#### SG05: Set triggers multiple subscribers
- **Setup**: Node with 3 subscribers via `use()`
- **Action**: `node.active:set(true)`
- **Assert**: All 3 callbacks invoked
- **Spec Ref**: Signal > use() (multiple)

#### SG06: Use runs effect immediately (no cleanup)
- **Setup**: Node with `name = "Alice"`
- **Action**: `node.name:use(function(v) record(v) end)`
- **Assert**: `record` called immediately with `"Alice"`
- **Spec Ref**: Signal > use()

#### SG07: Use cleanup runs after change
- **Setup**: Node with subscriber returning cleanup
- **Action**: `node.age:set(31)`
- **Assert**: Cleanup from previous value runs before new effect
- **Spec Ref**: Signal > use() Pattern

#### SG08: Unsub runs cleanup before next change
- **Setup**: Multiple subscribers with cleanup
- **Action**: `unsub()` then `node.name:set("Charlie")`
- **Assert**: Unsubscribed cleanup ran; unsubscribed effect did not run
- **Spec Ref**: Signal > use() Pattern

#### SG09: Use with nil value and cleanup
- **Setup**: Property set to nil
- **Action**: `use()` with cleanup function
- **Assert**: Effect receives nil; cleanup runs on unsub
- **Spec Ref**: Signal > use() Pattern

---

### Section 3: EdgeHandle Tests (EH-*)

#### 2-Wise Covering Array for EH Factors

```
| Test | EH.1   | EH.2 | EH.3 | EH.4    | EH.5     |
|------|--------|------|------|---------|----------|
| EH01 | link   | 0    | yes  | none    | -        |
| EH02 | link   | 1    | no   | onLink  | -        |
| EH03 | unlink | 1    | yes  | onUnlink| -        |
| EH04 | unlink | many | no   | each    | -        |
| EH05 | iter   | 0    | yes  | none    | none     |
| EH06 | iter   | many | no   | none    | equality |
| EH07 | count  | 0    | yes  | none    | -        |
| EH08 | count  | many | no   | none    | -        |
| EH09 | filter | many | yes  | none    | range    |
| EH10 | filter | 1    | no   | each    | compound |
| EH11 | each   | 0    | yes  | -       | -        |
| EH12 | each   | many | no   | -       | equality |
```

#### EH01: Link to empty edge with reverse
- **Setup**: User and Post nodes; edge "posts" with reverse "author"
- **Action**: `user.posts:link(post)`
- **Assert**: `user.posts:count() == 1`; `post.author:count() == 1`
- **Spec Ref**: EdgeHandle > link(), reverse edges

#### EH02: Link triggers onLink subscriber
- **Setup**: Edge with `onLink` subscriber
- **Action**: `user.posts:link(post)`
- **Assert**: onLink callback received `post` node
- **Spec Ref**: EdgeHandle > onLink()

#### EH03: Unlink from edge with reverse
- **Setup**: Linked user-post
- **Action**: `user.posts:unlink(post)`
- **Assert**: `user.posts:count() == 0`; `post.author:count() == 0`
- **Spec Ref**: EdgeHandle > unlink()

#### EH04: Unlink triggers onUnlink and each cleanup
- **Setup**: Edge with `each` subscriber tracking posts
- **Action**: `user.posts:unlink(post)`
- **Assert**: `each` cleanup invoked for removed post
- **Spec Ref**: EdgeHandle > each() Pattern

#### EH05: Iter on empty edge yields nothing
- **Setup**: No links on edge
- **Action**: Iterate `user.posts:iter()`
- **Assert**: Zero iterations
- **Spec Ref**: EdgeHandle > iter()

#### EH06: Iter with equality filter
- **Setup**: Multiple posts, some published
- **Action**: `user.posts:filter({ filters = {{ field = "published", op = "eq", value = true }} }):iter()`
- **Assert**: Only published posts yielded
- **Spec Ref**: EdgeHandle > filter()

#### EH07: Count on empty edge returns 0
- **Setup**: No links
- **Action**: `user.posts:count()`
- **Assert**: Returns 0
- **Spec Ref**: EdgeHandle > count()

#### EH08: Count on populated edge
- **Setup**: 3 linked posts
- **Action**: `user.posts:count()`
- **Assert**: Returns 3
- **Spec Ref**: EdgeHandle > count()

#### EH09: Filter with range operator
- **Setup**: Posts with views: 10, 50, 100
- **Action**: `user.posts:filter({ filters = {{ field = "views", op = "gt", value = 20 }} }):iter()`
- **Assert**: Returns posts with views 50 and 100
- **Spec Ref**: EdgeHandle > filter(), Filter operators

#### EH10: Filter with compound filters
- **Setup**: Posts with varying published and views
- **Action**: `filter({ filters = [{ published = true }, { views >= 10 }] })`
- **Assert**: Only matching posts returned
- **Spec Ref**: EdgeHandle > filter()

#### EH11: Each on empty edge
- **Setup**: Empty edge
- **Action**: `user.posts:each(fn)`
- **Assert**: Effect never called initially; returns unsub
- **Spec Ref**: EdgeHandle > each()

#### EH12: Each tracks membership with filter
- **Setup**: Filtered each on edge
- **Action**: Link matching post, then change to non-matching
- **Assert**: Effect called on link; cleanup called when filter no longer matches
- **Spec Ref**: EdgeHandle > each(), filter interaction

---

### Section 4: Rollup Tests (RL-*)

#### 3-Wise Covering Array for RL Factors (Critical Subsystem)

```
| Test | RL.1       | RL.2  | RL.3 | RL.4 | RL.5 | RL.6              |
|------|------------|-------|------|------|------|-------------------|
| RL01 | property   | count | no   | -    | 0    | edge_link         |
| RL02 | property   | count | yes  | -    | many | edge_unlink       |
| RL03 | property   | sum   | no   | -    | many | target_prop_change|
| RL04 | property   | avg   | no   | -    | 0    | -                 |
| RL05 | property   | avg   | no   | -    | many | target_prop_change|
| RL06 | property   | min   | no   | -    | many | edge_link         |
| RL07 | property   | max   | no   | -    | 1    | target_prop_change|
| RL08 | property   | first | no   | -    | many | edge_link         |
| RL09 | property   | last  | no   | -    | many | edge_unlink       |
| RL10 | property   | any   | yes  | -    | 0    | edge_link         |
| RL11 | property   | all   | no   | -    | many | target_prop_change|
| RL12 | reference  | -     | no   | yes  | 0    | edge_link         |
| RL13 | reference  | -     | yes  | yes  | many | target_prop_change|
| RL14 | reference  | -     | no   | yes  | 1    | edge_unlink       |
| RL15 | collection | -     | yes  | no   | many | edge_link         |
| RL16 | collection | -     | no   | yes  | many | target_prop_change|
| RL17 | collection | -     | yes  | yes  | 0    | edge_unlink       |
```

#### RL01: Property rollup count starts at 0
- **Setup**: User with `post_count` rollup (count of posts)
- **Action**: Create user with no posts
- **Assert**: `user.post_count:get() == 0`
- **Spec Ref**: Property Rollup > count

#### RL02: Property rollup count with filter decrements on unlink
- **Setup**: User with `published_count` rollup (count where published=true); 2 published posts
- **Action**: Unlink one published post
- **Assert**: `user.published_count:get() == 1`
- **Spec Ref**: Property Rollup > count, filters

#### RL03: Property rollup sum updates on target property change
- **Setup**: User with `total_views` rollup (sum of posts.views); posts with views 10, 20
- **Action**: Change one post's views to 30
- **Assert**: `user.total_views:get() == 50`
- **Spec Ref**: Property Rollup > sum, Rollup Update Triggers

#### RL04: Property rollup avg returns nil when empty
- **Setup**: User with `avg_views` rollup, no posts
- **Action**: `user.avg_views:get()`
- **Assert**: Returns nil
- **Spec Ref**: Property Rollup > avg

#### RL05: Property rollup avg computes correctly
- **Setup**: Posts with views 10, 20, 30
- **Action**: `user.avg_views:get()`
- **Assert**: Returns 20
- **Spec Ref**: Property Rollup > avg

#### RL06: Property rollup min updates on link
- **Setup**: Posts with views 20, 30; `min_views` rollup
- **Action**: Link post with views=10
- **Assert**: `user.min_views:get() == 10`
- **Spec Ref**: Property Rollup > min

#### RL07: Property rollup max updates on target change
- **Setup**: Post with views=100 linked; `max_views` rollup
- **Action**: Change post views to 50
- **Assert**: `user.max_views:get() == 50`
- **Spec Ref**: Property Rollup > max

#### RL08: Property rollup first returns first target's property
- **Setup**: Posts linked in order; `first_post_title` rollup
- **Action**: Link new post at beginning (by sort order)
- **Assert**: `first_post_title:get()` returns new post's title
- **Spec Ref**: Property Rollup > first

#### RL09: Property rollup last updates on unlink
- **Setup**: 3 posts; `last_post_title` rollup; unlink last
- **Action**: Unlink the last post
- **Assert**: Rollup now returns previous post's title
- **Spec Ref**: Property Rollup > last

#### RL10: Property rollup any becomes true on first match
- **Setup**: `has_published` rollup (any where published=true); no published posts
- **Action**: Link published post
- **Assert**: `user.has_published:get() == true`
- **Spec Ref**: Property Rollup > any

#### RL11: Property rollup all tracks truthiness
- **Setup**: All posts have featured=true; `all_featured` rollup
- **Action**: Change one post's featured to false
- **Assert**: `user.all_featured:get() == false`
- **Spec Ref**: Property Rollup > all

#### RL12: Reference rollup empty yields nothing
- **Setup**: `latest_post` reference rollup; no posts
- **Action**: Iterate `user.latest_post:iter()`
- **Assert**: Zero iterations; `count() == 0`
- **Spec Ref**: Reference Rollup

#### RL13: Reference rollup changes on sort property update
- **Setup**: Posts with created_at values; `latest_post` sorts by created_at desc
- **Action**: Update older post to have newest created_at
- **Assert**: `latest_post:iter()` now yields the updated post
- **Spec Ref**: Reference Rollup, sort

#### RL14: Reference rollup handles single unlink
- **Setup**: One post linked; reference rollup
- **Action**: Unlink the post
- **Assert**: `latest_post:count() == 0`
- **Spec Ref**: Reference Rollup

#### RL15: Collection rollup includes matching on link
- **Setup**: `published_posts` collection (filter published=true)
- **Action**: Link a published post
- **Assert**: Post appears in `published_posts:iter()`
- **Spec Ref**: Collection Rollup

#### RL16: Collection rollup reacts to filter field change
- **Setup**: Post in `published_posts` collection
- **Action**: Change post.published to false
- **Assert**: Post no longer in `published_posts:iter()`
- **Spec Ref**: Collection Rollup, Rollup Update Triggers

#### RL17: Collection rollup sorted empty
- **Setup**: `published_posts` with sort; no matching posts
- **Action**: `published_posts:count()`
- **Assert**: Returns 0
- **Spec Ref**: Collection Rollup

---

### Section 5: Index Tests (IX-*)

#### 2-Wise Covering Array for IX Factors

```
| Test | IX.1 | IX.2  | IX.3    | IX.4 | IX.5 |
|------|------|-------|---------|------|------|
| IX01 | 1    | asc   | full    | no   | yes  |
| IX02 | 1    | desc  | partial | yes  | no   |
| IX03 | 2+   | asc   | none    | no   | no   |
| IX04 | 2+   | desc  | full    | yes  | yes  |
| IX05 | 2+   | mixed | partial | no   | yes  |
| IX06 | 1    | asc   | none    | yes  | no   |
```

#### IX01: Single field index covers equality filter
- **Setup**: Index on `name` asc; filter `name = "Alice"`
- **Action**: Query view with filter
- **Assert**: Uses index; results in correct order
- **Spec Ref**: Index Coverage (equality prefix)

#### IX02: Single field index partial coverage with range
- **Setup**: Index on `age` desc; filter `age > 20 AND name = "Alice"`
- **Action**: Query view
- **Assert**: Index used for age; post-filter for name
- **Spec Ref**: Index Coverage (range filter)

#### IX03: Compound index not used (no coverage)
- **Setup**: Index on `(name, age)`; filter `status = "active"`
- **Action**: Query view
- **Assert**: Falls back to default index
- **Spec Ref**: Index Coverage (no gaps rule)

#### IX04: Compound index full coverage with range and sort
- **Setup**: Index on `(status, age)` desc; filter `status = "active" AND age > 20`
- **Action**: Query view
- **Assert**: Index fully covers query; sort matches
- **Spec Ref**: Index Coverage (all rules)

#### IX05: Compound index partial with sort match
- **Setup**: Index on `(name asc, age desc)`; filter `name = "Alice"` sort by age
- **Action**: Query view
- **Assert**: Equality prefix used; sort on remaining field
- **Spec Ref**: Index Coverage (sort field rule)

#### IX06: Single field index unused, range filter present
- **Setup**: Index on `name`; filter `age > 20`
- **Action**: Query view
- **Assert**: Index not used for filtering
- **Spec Ref**: Index Coverage

---

### Section 6: View Tests (VW-*)

#### 3-Wise Covering Array for VW Factors (Critical Subsystem)

```
| Test | VW.1     | VW.2   | VW.3   | VW.4    | VW.5        | VW.6      | VW.7           |
|------|----------|--------|--------|---------|-------------|-----------|----------------|
| VW01 | none     | 0      | start  | default | tree        | on_enter  | initial        |
| VW02 | equality | 0      | middle | default | tree        | on_leave  | delete         |
| VW03 | range    | 0      | end    | eager   | tree        | on_change | runtime_change |
| VW04 | none     | 1      | start  | default | tree        | on_enter  | runtime_change |
| VW05 | equality | 1      | middle | inline  | tree        | on_change | runtime_change |
| VW06 | none     | 2+     | start  | default | tree        | on_enter  | initial        |
| VW07 | range    | 2+     | end    | default | tree        | on_leave  | collapse       |
| VW08 | none     | 1      | start  | default | multi_parent| on_change | runtime_change |
| VW09 | equality | 1      | middle | default | multi_parent| on_enter  | runtime_change |
| VW10 | none     | 2+     | start  | default | multi_parent| on_change | runtime_change |
| VW11 | none     | 0      | start  | eager   | tree        | on_expand | initial        |
| VW12 | none     | 1      | start  | default | tree        | on_collapse| collapse      |
```

#### VW01: View with no filters, root only, initial on_enter
- **Setup**: Users in graph; view with no filters
- **Action**: Create view with `on_enter` callback
- **Assert**: `on_enter` fires for each root with position; `item.depth == 0`
- **Spec Ref**: Views > callbacks, Deep Reactivity

#### VW02: View with equality filter, root delete fires on_leave
- **Setup**: View filtering `active = true`; 3 users
- **Action**: Delete one active user
- **Assert**: `on_leave` fires for deleted user; `total()` decrements
- **Spec Ref**: Views > on_leave, Reactivity

#### VW03: View with range filter, property change fires on_change
- **Setup**: View filtering `age > 20`; eager expansion
- **Action**: Change matching user's name
- **Assert**: `on_change` fires with (node, "name", new, old)
- **Spec Ref**: Views > on_change, Deep Reactivity

#### VW04: View one-level expansion, on_enter fires for children
- **Setup**: User with 3 posts
- **Action**: `view:expand(user._id, "posts")`
- **Assert**: `on_enter` fires for each post; `item.depth == 1`; `item.edge == "posts"`
- **Spec Ref**: Views > expand(), Deep Reactivity

#### VW05: Inline children, change fires on_change
- **Setup**: View with `inline = true` for edge; expanded
- **Action**: Change child property
- **Assert**: `on_change` fires; child `item.depth` same as parent
- **Spec Ref**: Views > inline, on_change

#### VW06: Nested expansion (2+ levels), on_enter for all levels
- **Setup**: User -> Post -> Comments structure
- **Action**: Expand posts, then expand comments on a post
- **Assert**: `on_enter` fires at each level; depths are 0, 1, 2
- **Spec Ref**: Views > nested expansion

#### VW07: Nested collapse fires on_leave for all descendants
- **Setup**: Nested expansion (user -> posts -> comments)
- **Action**: `view:collapse(user._id, "posts")`
- **Assert**: `on_leave` fires for all posts and their comments
- **Spec Ref**: Views > collapse(), Deep Reactivity

#### VW08: Multi-parent node, on_change fires per path
- **Setup**: Post linked to 2 users; both users expanded in view
- **Action**: Change post title
- **Assert**: `on_change` fires twice (once per parent path)
- **Spec Ref**: Views > Multi-parent DAG support

#### VW09: Multi-parent node, on_enter fires per path
- **Setup**: Post already linked to user1; user1 expanded
- **Action**: Link same post to user2; expand user2's posts
- **Assert**: `on_enter` fires for post under user2 (already visible under user1)
- **Spec Ref**: Views > Multi-parent DAG support

#### VW10: Deep multi-parent, on_change fires per nested path
- **Setup**: Comment linked under post1 and post2; both posts expanded under same user
- **Action**: Change comment text
- **Assert**: `on_change` fires once per path (2 times)
- **Spec Ref**: Views > Multi-parent, Deep Reactivity

#### VW11: Eager expansion fires on_expand at creation
- **Setup**: View with `eager = true` for posts edge
- **Action**: Create view
- **Assert**: Posts automatically expanded; `on_expand` fired
- **Spec Ref**: Views > eager

#### VW12: Collapse fires on_collapse callback
- **Setup**: Expanded edge
- **Action**: `view:collapse(id, "posts")`
- **Assert**: `on_collapse` callback fires with (id, "posts")
- **Spec Ref**: Views > on_collapse

---

### Section 7: View Methods Tests (VM-*)

#### VM01: items() returns iterator
- **Setup**: View with 5 roots
- **Action**: `for item in view:items() do count = count + 1 end`
- **Assert**: count == min(5, limit)
- **Spec Ref**: View Methods > items()

#### VM02: total() returns root count
- **Setup**: View with filter matching 3 of 5 nodes
- **Action**: `view:total()`
- **Assert**: Returns 3
- **Spec Ref**: View Methods > total()

#### VM03: visible_total() includes expansions
- **Setup**: 2 roots, one expanded with 3 children
- **Action**: `view:visible_total()`
- **Assert**: Returns 5 (2 roots + 3 children)
- **Spec Ref**: View Methods > visible_total()

#### VM04: collect() returns list
- **Setup**: View with items
- **Action**: `view:collect()`
- **Assert**: Returns array of item tables
- **Spec Ref**: View Methods > collect()

#### VM05: scroll() changes offset
- **Setup**: View with 10 items, limit 5
- **Action**: `view:scroll(5)`
- **Assert**: `items()` now yields items 6-10
- **Spec Ref**: View Methods > scroll()

#### VM06: expand() returns true on success
- **Setup**: Node with children
- **Action**: `view:expand(id, "posts")`
- **Assert**: Returns true; `visible_total()` increases
- **Spec Ref**: View Methods > expand()

#### VM07: expand() returns false if already expanded
- **Setup**: Already expanded edge
- **Action**: `view:expand(id, "posts")` again
- **Assert**: Returns false
- **Spec Ref**: View Methods > expand()

#### VM08: collapse() cleans up subscriptions
- **Setup**: Expanded edge with children
- **Action**: `view:collapse(id, "posts")`
- **Assert**: Returns true; child subscriptions removed
- **Spec Ref**: View Methods > collapse(), Deep View Reactivity

#### VM09: destroy() unsubscribes all
- **Setup**: View with expanded nodes
- **Action**: `view:destroy()`
- **Assert**: No callbacks fire on subsequent changes
- **Spec Ref**: View Methods > destroy()

---

### Section 8: Interaction Tests (IT-*)

These tests verify cross-subsystem interactions identified in the factor analysis.

#### IT01: Signal.use() on property rollup
- **Setup**: User with `post_count` property rollup
- **Action**: `user.post_count:use(fn)`; link a post
- **Assert**: Effect fires with new count
- **Spec Ref**: Property Rollup (Signal-like interface)

#### IT02: EdgeHandle.link() triggers rollup update
- **Setup**: User with `total_views` sum rollup
- **Action**: `user.posts:link(post_with_views_50)`
- **Assert**: `user.total_views:get()` includes new post's views
- **Spec Ref**: Rollup Update Triggers

#### IT03: Property rollup usable in index
- **Setup**: Index on `post_count` field; property rollup for `post_count`
- **Action**: Query view sorted by `post_count`
- **Assert**: Results in correct order by rollup value
- **Spec Ref**: Using Property Rollups in Indexes

#### IT04: View uses covering index
- **Setup**: Index on `(status, age)`; view filters `status = "active"`
- **Action**: Create view; verify query performance
- **Assert**: Index selected; results filtered correctly
- **Spec Ref**: Index Coverage, Views

#### IT05: Deep view expansion tracks nested rollups
- **Setup**: View with expanded posts; posts have comment_count rollup
- **Action**: Link comment to expanded post
- **Assert**: `on_change` fires for post's comment_count change
- **Spec Ref**: Deep Reactivity, Rollup Update Triggers

#### IT06: Multi-parent unlink fires on_leave only for affected path
- **Setup**: Post under user1 and user2 (both expanded)
- **Action**: `user1.posts:unlink(post)`
- **Assert**: `on_leave` fires once (for user1 path); post still visible under user2
- **Spec Ref**: Multi-parent DAG support, EdgeHandle

---

## Coverage Matrix

### Spec Section to Test Mapping

| Spec Section | Tests |
|--------------|-------|
| Graph Creation | NP01-04 |
| Graph Structure | NP01, NP05 |
| Node IDs | NP01 |
| Property Values | NP01-04, NP09, SG01-02 |
| Schema | NP01-04 |
| Edge Definition | EH01, EH03 |
| Rollup Definitions | RL01-17 |
| Node Proxy API | NP05, SG*, EH01-04 |
| Signal | SG01-09 |
| EdgeHandle | EH01-12 |
| Property Rollup | RL01-11, IT01 |
| Reference Rollup | RL12-14 |
| Collection Rollup | RL15-17 |
| Index Coverage | IX01-06, IT04 |
| Graph Methods | NP01-11, EH01-04 |
| Views | VW01-12, VM01-09 |
| Virtualized Strategy | VM03, VM06-08 |
| Deep Reactivity | VW04-10, IT05 |
| Multi-parent DAG | VW08-10, IT06 |
| Reactivity | IT01-02, VW03, RL03-16 |

### Factor Coverage Summary

| Subsystem | Factors | Levels | Tests | Coverage |
|-----------|---------|--------|-------|----------|
| Node/Property | 4 | 11 | 11 | 2-wise |
| Signal | 5 | 13 | 9 | 2-wise |
| EdgeHandle | 5 | 18 | 12 | 2-wise |
| Rollup | 6 | 23 | 17 | 3-wise |
| Index | 5 | 12 | 6 | 2-wise |
| View | 7 | 21 | 12 | 3-wise |
| View Methods | - | - | 9 | Exhaustive |
| Interactions | - | - | 6 | Key pairs |

**Total Test Specifications: 82**

---

## Appendix: Orthogonal Array Generation

The covering arrays in this document were generated to satisfy:

1. **2-wise coverage** for factors with fewer interaction effects
2. **3-wise coverage** for Rollup and View subsystems (high interaction complexity)
3. **All pairs** for cross-subsystem interactions

### Why These Factors?

Each factor was selected because it represents an **independent axis of variation** in the spec:

- **Operation types** determine which code paths execute
- **Data types** affect comparison, storage, and nil handling
- **Cardinality** (0, 1, many) reveals boundary conditions
- **Configuration options** (filters, sort, indexes) affect query optimization
- **Structural patterns** (tree vs DAG) affect callback behavior

### Why N-Wise?

Full combinatorial testing of all factors would require:
- 4 × 4 × 2 × 2 = 64 tests for Node/Property alone
- Millions of tests for the full system

N-wise testing reduces this to ~82 tests while guaranteeing:
- Every factor level is tested
- Every pair (2-wise) or triple (3-wise) of interactions is covered
- Critical edge cases are exercised

---

## Appendix B: Extended Test Dimensions

This appendix defines additional test dimensions derived from implementation patterns discovered during initial compliance validation. These patterns expose potential edge cases not covered by the primary test suite.

### B.1 Edge Symmetry Tests (ES-*)

**Root Pattern**: Edge storage is asymmetric - forward edges store in `edges[src][name]`, reverse edges store in `reverse[tgt][reverse_name]`. Only the initiating side maintains `edge_counts`.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Link Initiator | `source`, `target` | Which side calls link() |
| Edge Config | `with_reverse`, `without_reverse` | Whether reverse is defined |
| Query Side | `from_source`, `from_target` | Which side queries count/iter |
| Operation | `count`, `iter`, `link`, `unlink` | The operation performed |

#### 2-Wise Covering Array

| ID | Link Initiator | Edge Config | Query Side | Operation |
|----|----------------|-------------|------------|-----------|
| ES01 | source | with_reverse | from_source | count |
| ES02 | source | with_reverse | from_target | count |
| ES03 | target | with_reverse | from_source | count |
| ES04 | target | with_reverse | from_target | count |
| ES05 | source | with_reverse | from_source | iter |
| ES06 | target | with_reverse | from_target | iter |
| ES07 | source | without_reverse | from_source | count |
| ES08 | source | with_reverse | from_source | unlink |
| ES09 | target | with_reverse | from_target | unlink |
| ES10 | source | with_reverse | from_target | link |
| ES11 | target | with_reverse | from_source | link |

#### Test Specifications

##### ES01: Count from source after source-initiated link
- **Setup**: User -> Post edge with reverse; link via `user.posts:link(post)`
- **Action**: `user.posts:count()`
- **Assert**: Returns 1

##### ES02: Count from target after source-initiated link
- **Setup**: User -> Post edge with reverse; link via `user.posts:link(post)`
- **Action**: `post.author:count()`
- **Assert**: Returns 1 (via reverse storage lookup)

##### ES03: Count from source after target-initiated link
- **Setup**: User -> Post edge with reverse; link via `post.author:link(user)`
- **Action**: `user.posts:count()`
- **Assert**: Returns 1 (via reverse storage lookup)

##### ES04: Count from target after target-initiated link
- **Setup**: User -> Post edge with reverse; link via `post.author:link(user)`
- **Action**: `post.author:count()`
- **Assert**: Returns 1

##### ES05: Iter from source after source-initiated link
- **Setup**: User -> Post edge with reverse; link via `user.posts:link(post)`
- **Action**: Collect `user.posts:iter()`
- **Assert**: Contains post

##### ES06: Iter from target after target-initiated link
- **Setup**: User -> Post edge with reverse; link via `post.author:link(user)`
- **Action**: Collect `post.author:iter()`
- **Assert**: Contains user

##### ES07: Count on edge without reverse
- **Setup**: User -> User (friends) edge without reverse; link via `user1.friends:link(user2)`
- **Action**: `user1.friends:count()`
- **Assert**: Returns 1

##### ES08: Unlink from source side
- **Setup**: Linked User -> Post; unlink via `user.posts:unlink(post)`
- **Action**: `post.author:count()`
- **Assert**: Returns 0

##### ES09: Unlink from target side
- **Setup**: Linked User -> Post; unlink via `post.author:unlink(user)`
- **Action**: `user.posts:count()`
- **Assert**: Returns 0

##### ES10: Double-link from both sides
- **Setup**: User -> Post edge with reverse
- **Action**: `user.posts:link(post)` then `post.author:link(user)`
- **Assert**: Count remains 1 (no duplicates)

##### ES11: Cross-side link detection
- **Setup**: User -> Post edge with reverse; link via `post.author:link(user)`
- **Action**: `user.posts:iter()`
- **Assert**: Contains post

---

### B.2 Subscription Lifecycle Tests (SL-*)

**Root Pattern**: Multiple components subscribe to nodes with ref-counting. Subscription timing relative to data mutations affects callback behavior.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Subscribe Timing | `before_data`, `after_data`, `during_mutation` | When subscription is created |
| Data State | `empty`, `populated`, `mutating` | State of data at subscribe time |
| Unsubscribe Timing | `before_change`, `after_change`, `never` | When unsubscribe is called |
| Subscriber Type | `signal_use`, `edge_each`, `view_callback` | Type of subscription |
| Nested Depth | `root`, `child`, `grandchild` | Depth in expansion tree |

#### 2-Wise Covering Array

| ID | Subscribe | Data State | Unsubscribe | Subscriber | Depth |
|----|-----------|------------|-------------|------------|-------|
| SL01 | before_data | empty | after_change | signal_use | root |
| SL02 | after_data | populated | never | signal_use | root |
| SL03 | before_data | populated | before_change | edge_each | root |
| SL04 | after_data | empty | after_change | edge_each | child |
| SL05 | during_mutation | mutating | never | view_callback | root |
| SL06 | before_data | empty | never | view_callback | child |
| SL07 | after_data | populated | before_change | view_callback | grandchild |
| SL08 | during_mutation | populated | after_change | signal_use | child |
| SL09 | before_data | mutating | after_change | edge_each | grandchild |

#### Test Specifications

##### SL01: Signal.use before data, unsubscribe after change
- **Setup**: Create node with nil property
- **Action**: Subscribe via `use()`, set property, unsubscribe, set again
- **Assert**: Effect fires once (not after unsub)

##### SL02: Signal.use after data exists, never unsubscribe
- **Setup**: Create node with property value
- **Action**: Subscribe via `use()`, change property twice
- **Assert**: Effect fires for initial + both changes

##### SL03: EdgeHandle.each before populated, unsubscribe before change
- **Setup**: Empty edge
- **Action**: Subscribe via `each()`, unsubscribe, then link node
- **Assert**: Effect never fires, no cleanup called

##### SL04: EdgeHandle.each after empty, with child depth
- **Setup**: View with expansion, empty child edge
- **Action**: Subscribe to child edge via `each()`, link grandchild
- **Assert**: Effect fires for grandchild

##### SL05: View callback during mutation
- **Setup**: View creation while insert is in progress
- **Action**: Insert node during view creation callback
- **Assert**: No double-fire, consistent state

##### SL06: View callback on child before data
- **Setup**: View with no data, expand edge
- **Action**: Link child node
- **Assert**: on_enter fires for child

##### SL07: View callback on grandchild, unsubscribe before change
- **Setup**: View with nested expansion
- **Action**: Collapse parent before grandchild mutation
- **Assert**: No callback for grandchild change

##### SL08: Signal during mutation at child depth
- **Setup**: View with expanded child
- **Action**: Subscribe to child property during link callback
- **Assert**: Subscription works correctly

##### SL09: Edge each on grandchild during mutation
- **Setup**: View with nested expansion during link
- **Action**: `each()` on grandchild edge while parent linking
- **Assert**: Consistent callback behavior

---

### B.3 Initialization Race Tests (IR-*)

**Root Pattern**: View initialization has distinct phases. Mutations during initialization may cause double-firing or missed callbacks.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Pre-existing Data | `none`, `roots_only`, `with_children` | Data state before view creation |
| Mutation During Init | `none`, `insert`, `link`, `delete`, `property_change` | Mutation type during creation |
| Eager Edges | `none`, `one_level`, `nested` | Eager expansion configuration |
| Callback Type | `on_enter`, `on_leave`, `on_change`, `on_expand` | Which callback is monitored |

#### 2-Wise Covering Array

| ID | Pre-existing | Mutation | Eager | Callback |
|----|--------------|----------|-------|----------|
| IR01 | none | none | none | on_enter |
| IR02 | roots_only | none | none | on_enter |
| IR03 | with_children | none | one_level | on_enter |
| IR04 | roots_only | insert | none | on_enter |
| IR05 | roots_only | link | one_level | on_enter |
| IR06 | with_children | delete | none | on_leave |
| IR07 | roots_only | property_change | none | on_change |
| IR08 | none | insert | one_level | on_expand |
| IR09 | with_children | none | nested | on_expand |
| IR10 | roots_only | link | nested | on_enter |

#### Test Specifications

##### IR01: Empty graph, no mutation, no eager
- **Setup**: Empty graph
- **Action**: Create view
- **Assert**: No callbacks fire

##### IR02: Roots exist, no mutation, no eager
- **Setup**: Graph with 2 root nodes
- **Action**: Create view
- **Assert**: on_enter fires exactly 2 times

##### IR03: Children exist, eager one level
- **Setup**: Root with 3 children linked
- **Action**: Create view with `eager = true` on child edge
- **Assert**: on_enter fires for root + 3 children

##### IR04: Insert during view creation
- **Setup**: 1 root exists
- **Action**: Create view, insert node in on_enter callback
- **Assert**: Second node gets on_enter (not during init)

##### IR05: Link during view creation with eager
- **Setup**: Root exists, child exists unlinked
- **Action**: Create view with eager, link child in root's on_enter
- **Assert**: Child on_enter fires exactly once

##### IR06: Delete during view creation
- **Setup**: 2 roots exist
- **Action**: Create view, delete one root in first on_enter
- **Assert**: on_leave fires for deleted, on_enter fires for remaining

##### IR07: Property change during view creation
- **Setup**: Root exists
- **Action**: Create view, change property in on_enter
- **Assert**: on_change does NOT fire (init phase)

##### IR08: Insert with eager expansion
- **Setup**: Empty graph, eager edge config
- **Action**: Create view, insert root with children
- **Assert**: on_expand fires, children get on_enter

##### IR09: Nested eager expansion
- **Setup**: Root -> Child -> Grandchild all linked
- **Action**: Create view with nested eager
- **Assert**: on_expand fires for both levels

##### IR10: Link during nested eager init
- **Setup**: Root exists, child and grandchild exist unlinked
- **Action**: Create view with nested eager, link child in root on_enter
- **Assert**: Proper cascade of on_enter and on_expand

---

### B.4 Multi-Parent Path Resolution Tests (MP-*)

**Root Pattern**: DAG nodes with multiple parents have multiple valid paths. Path resolution affects which callbacks fire and with what context.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Parent Count | `1`, `2`, `3+` | Number of parents for target node |
| Expansion State | `none`, `one_parent`, `all_parents` | Which parent edges are expanded |
| Operation | `expand`, `collapse`, `property_change`, `unlink` | Operation on multi-parent node |
| Path Selection | `first_found`, `specific_parent` | How path is selected for operation |

#### 2-Wise Covering Array

| ID | Parents | Expansion | Operation | Path Selection |
|----|---------|-----------|-----------|----------------|
| MP01 | 2 | one_parent | property_change | first_found |
| MP02 | 2 | all_parents | property_change | first_found |
| MP03 | 3+ | one_parent | expand | first_found |
| MP04 | 2 | all_parents | expand | specific_parent |
| MP05 | 3+ | all_parents | collapse | first_found |
| MP06 | 2 | one_parent | unlink | specific_parent |
| MP07 | 3+ | none | property_change | first_found |
| MP08 | 2 | all_parents | unlink | first_found |
| MP09 | 1 | one_parent | collapse | first_found |

#### Test Specifications

##### MP01: Property change with one parent expanded
- **Setup**: Node with 2 parents, only parent1's edge expanded
- **Action**: Change property on multi-parent node
- **Assert**: on_change fires once (for visible path)

##### MP02: Property change with all parents expanded
- **Setup**: Node with 2 parents, both edges expanded
- **Action**: Change property on multi-parent node
- **Assert**: on_change fires twice (once per path)

##### MP03: Expand on 3-parent node via first found
- **Setup**: Node with 3 parents, one expanded to show node
- **Action**: Expand child edge on multi-parent node
- **Assert**: Expansion applies to first-found path

##### MP04: Expand on specific parent path
- **Setup**: Node with 2 parents, both expanded
- **Action**: Expand via specific path (using item from collect)
- **Assert**: Expansion tracked correctly per path

##### MP05: Collapse with 3+ parents all expanded
- **Setup**: Node with 3 parents, all expanded, child edge expanded
- **Action**: Collapse child edge
- **Assert**: on_leave fires for children on all paths

##### MP06: Unlink from specific parent
- **Setup**: Node with 2 parents, one expanded
- **Action**: Unlink from the expanded parent
- **Assert**: on_leave fires, other parent relationship intact

##### MP07: Property change with no expansions
- **Setup**: Node with 3 parents, no edges expanded
- **Action**: Change property on multi-parent node
- **Assert**: No on_change (node not visible in view)

##### MP08: Unlink multi-parent with all expanded
- **Setup**: Node with 2 parents, both expanded
- **Action**: Unlink from one parent
- **Assert**: on_leave fires once, node still visible via other parent

##### MP09: Collapse single-parent baseline
- **Setup**: Node with 1 parent, edge expanded with children
- **Action**: Collapse edge
- **Assert**: on_leave fires for all children

---

### B.5 Raw/Proxy Boundary Tests (RP-*)

**Root Pattern**: Internal code uses raw nodes (`graph.nodes[id]`), external API uses proxies (`graph:get(id)`). Boundary violations cause missing Signal wrappers.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Access Point | `graph_get`, `callback_param`, `item_node`, `iter_result` | Where node is accessed |
| Property Access | `direct`, `via_signal`, `type_field`, `id_field` | How property is accessed |
| Node State | `exists`, `deleted`, `mutating` | State of node |

#### 2-Wise Covering Array

| ID | Access Point | Property Access | Node State |
|----|--------------|-----------------|------------|
| RP01 | graph_get | via_signal | exists |
| RP02 | callback_param | via_signal | exists |
| RP03 | item_node | via_signal | exists |
| RP04 | iter_result | via_signal | exists |
| RP05 | graph_get | direct | exists |
| RP06 | callback_param | type_field | exists |
| RP07 | item_node | id_field | exists |
| RP08 | iter_result | type_field | deleted |
| RP09 | graph_get | via_signal | deleted |

#### Test Specifications

##### RP01: graph:get returns proxy with Signal access
- **Setup**: Node with properties
- **Action**: `graph:get(id).name:get()`
- **Assert**: Returns value, `:get()` works

##### RP02: Callback param is proxy
- **Setup**: View with on_enter callback
- **Action**: Access `node.name:get()` in callback
- **Assert**: Returns value, `:get()` works

##### RP03: Item.node is proxy
- **Setup**: View with items
- **Action**: `view:collect()[1].node.name:get()`
- **Assert**: Returns value, `:get()` works

##### RP04: Edge iter result is proxy
- **Setup**: Edge with linked nodes
- **Action**: `for n in edge:iter() do n.name:get() end`
- **Assert**: Returns value, `:get()` works

##### RP05: Direct property access errors
- **Setup**: Node with properties
- **Action**: `graph:get(id).name` (without :get())
- **Assert**: Returns Signal object, not raw value

##### RP06: Callback param has _type
- **Setup**: View with on_enter callback
- **Action**: Access `node._type` in callback
- **Assert**: Returns type string

##### RP07: Item.node has _id
- **Setup**: View with items
- **Action**: `view:collect()[1].node._id`
- **Assert**: Returns numeric ID

##### RP08: Iter on deleted node
- **Setup**: Edge with linked node, delete node
- **Action**: Iterate edge
- **Assert**: Deleted node not yielded

##### RP09: graph:get on deleted node
- **Setup**: Node exists, then deleted
- **Action**: `graph:get(id)`
- **Assert**: Returns nil

---

### B.6 Index Coupling Tests (IC-*)

**Root Pattern**: Rollups and Views require covering indexes. Missing indexes cause errors, not fallback behavior.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| Component | `view`, `rollup_property`, `rollup_reference`, `edge_filter` | What requires the index |
| Index State | `exists_covering`, `exists_partial`, `missing` | Index availability |
| Query Type | `equality`, `range`, `sort`, `compound` | Type of query |

#### 2-Wise Covering Array

| ID | Component | Index State | Query Type |
|----|-----------|-------------|------------|
| IC01 | view | exists_covering | equality |
| IC02 | view | missing | equality |
| IC03 | rollup_property | exists_covering | equality |
| IC04 | rollup_reference | exists_covering | sort |
| IC05 | rollup_reference | missing | sort |
| IC06 | edge_filter | exists_covering | range |
| IC07 | edge_filter | missing | range |
| IC08 | view | exists_partial | compound |
| IC09 | rollup_property | exists_covering | compound |

#### Test Specifications

##### IC01: View with covering equality index
- **Setup**: Index on filter field
- **Action**: Create view with equality filter
- **Assert**: View created successfully

##### IC02: View with missing index
- **Setup**: No index on filter field
- **Action**: Create view with equality filter
- **Assert**: Error "No index covers query"

##### IC03: Property rollup with covering filter index
- **Setup**: Edge index on filter field
- **Action**: Access filtered rollup
- **Assert**: Rollup value computed correctly

##### IC04: Reference rollup with sort index
- **Setup**: Edge index on sort field
- **Action**: Access sorted reference rollup
- **Assert**: Returns correctly sorted first item

##### IC05: Reference rollup missing sort index
- **Setup**: No edge index on sort field
- **Action**: Define reference rollup with sort
- **Assert**: Falls back to default index (unsorted)

##### IC06: Edge filter with range index
- **Setup**: Edge index on filter field
- **Action**: `edge:filter({ filters = { field > value } })`
- **Assert**: Filter works correctly

##### IC07: Edge filter missing index
- **Setup**: No edge index on filter field
- **Action**: `edge:filter({ filters = { field > value } })`
- **Assert**: Error "No index covers query"

##### IC08: View with partial compound index
- **Setup**: Compound index, query uses subset
- **Action**: Create view with partial match
- **Assert**: Uses index for covered prefix

##### IC09: Property rollup compound filter
- **Setup**: Edge with compound index
- **Action**: Rollup with multi-field filter
- **Assert**: Uses compound index correctly

---

### Summary: Extended Test Matrix

| Section | Tests | Coverage | Pattern Addressed |
|---------|-------|----------|-------------------|
| ES (Edge Symmetry) | 11 | 2-wise | Bidirectional storage asymmetry |
| SL (Subscription Lifecycle) | 9 | 2-wise | Ref-counting and timing |
| IR (Initialization Race) | 10 | 2-wise | View init phase mutations |
| MP (Multi-Parent Paths) | 9 | 2-wise | DAG path resolution |
| RP (Raw/Proxy Boundary) | 9 | 2-wise | Node access consistency |
| IC (Index Coupling) | 9 | 2-wise | Index requirement enforcement |

**Additional Test Specifications: 57**
**Total with Extended: 139**

---

## Appendix C: Additional Feature Coverage

This appendix covers features that exist in the implementation but were not included in the primary test suite or Appendix B. These features have lower usage frequency but require coverage to ensure correctness.

### C.1 Recursive Edge Tests (RE-*)

**Root Pattern**: The `recursive` edge configuration flag allows the same edge type to be expanded at any depth in the tree. This creates potential for infinite expansion, complex path tracking, and interaction with other edge flags.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| RE.1 Depth | `1`, `2`, `3+` | How deep the recursive structure goes |
| RE.2 Structure | `tree`, `multi_parent` | Whether nodes have single or multiple parents |
| RE.3 Combined With | `none`, `eager`, `inline` | Other edge config flags |
| RE.4 Operation | `expand`, `collapse`, `property_change` | What triggers callbacks |
| RE.5 Termination | `leaf_nodes`, `max_depth`, `manual` | How expansion stops |

#### 3-Wise Covering Array (Critical - High Interaction Risk)

| ID | Depth | Structure | Combined | Operation | Termination |
|----|-------|-----------|----------|-----------|-------------|
| RE01 | 1 | tree | none | expand | leaf_nodes |
| RE02 | 2 | tree | none | expand | leaf_nodes |
| RE03 | 3+ | tree | none | expand | leaf_nodes |
| RE04 | 2 | tree | eager | expand | max_depth |
| RE05 | 3+ | tree | eager | expand | leaf_nodes |
| RE06 | 2 | tree | inline | expand | leaf_nodes |
| RE07 | 2 | multi_parent | none | expand | leaf_nodes |
| RE08 | 3+ | multi_parent | none | property_change | manual |
| RE09 | 2 | tree | none | collapse | manual |
| RE10 | 3+ | tree | eager | collapse | leaf_nodes |
| RE11 | 2 | multi_parent | inline | property_change | leaf_nodes |
| RE12 | 3+ | multi_parent | eager | expand | max_depth |

#### Test Specifications

##### RE01: Single-level recursive expand
- **Setup**: Category with subcategories (self-referential edge `children`); 1 level deep
- **Action**: `view:expand(root._id, "children")`
- **Assert**: Children visible; `on_enter` fires for each child; `item.depth == 1`

##### RE02: Two-level recursive expand
- **Setup**: Category tree 2 levels deep; `children` edge marked `recursive = true`
- **Action**: Expand root, then expand a child
- **Assert**: Grandchildren visible at `depth == 2`; same edge name at each level

##### RE03: Deep recursive expand (3+ levels)
- **Setup**: Category tree 4 levels deep
- **Action**: Expand at each level
- **Assert**: All levels visible; depths are 1, 2, 3, 4; `on_enter` fires at each expansion

##### RE04: Recursive with eager (limited depth)
- **Setup**: `recursive = true, eager = true` on `children` edge; 3 level tree
- **Action**: Create view
- **Assert**: Only first level auto-expands (eager doesn't recurse infinitely)

##### RE05: Deep recursive with eager at leaves
- **Setup**: 3-level tree; leaves have no children
- **Action**: Create view with eager recursive edge
- **Assert**: Expansion stops at leaves; no infinite loop

##### RE06: Recursive with inline
- **Setup**: `recursive = true, inline = true` on `children` edge
- **Action**: Expand 2 levels
- **Assert**: All items have `depth == 0` (inline flattens)

##### RE07: Recursive on multi-parent DAG
- **Setup**: Category appears under 2 parent categories; recursive edge
- **Action**: Expand both parents to show shared child
- **Assert**: Shared category visible twice; correct path context for each

##### RE08: Property change in deep recursive multi-parent
- **Setup**: Node at depth 3, visible via 2 paths
- **Action**: Change property on deep node
- **Assert**: `on_change` fires twice (once per path)

##### RE09: Collapse recursive at mid-level
- **Setup**: 3-level recursive expansion
- **Action**: Collapse at level 1
- **Assert**: `on_leave` fires for all descendants (levels 2 and 3)

##### RE10: Collapse eager recursive
- **Setup**: Eager recursive edge, 3 levels auto-expanded
- **Action**: Collapse root edge
- **Assert**: All descendants collapsed; `on_leave` fires for all

##### RE11: Multi-parent with inline recursive
- **Setup**: Shared node in recursive inline structure
- **Action**: Change property on shared node
- **Assert**: `on_change` fires with correct (flattened) depth

##### RE12: Deep multi-parent with eager recursive
- **Setup**: DAG with shared nodes, 3+ levels, eager recursive
- **Action**: Create view
- **Assert**: Shared nodes appear at correct positions in each path; no infinite loop

---

### C.2 Edge Configuration Extension Tests (EC-*)

**Root Pattern**: Edge configurations in views support `sort` and `filters` to control which children are visible and in what order. These interact with callbacks and expansion state.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| EC.1 Config Type | `sort_only`, `filter_only`, `sort_and_filter` | Which configs are applied |
| EC.2 Sort Direction | `asc`, `desc` | Sort order |
| EC.3 Filter Type | `equality`, `range` | Type of filter condition |
| EC.4 Data Mutation | `add_match`, `add_non_match`, `change_to_match`, `change_to_non_match` | How data changes |
| EC.5 Callback | `on_enter`, `on_leave`, `on_change` | Which callback is affected |

#### 2-Wise Covering Array

| ID | Config Type | Sort Dir | Filter Type | Mutation | Callback |
|----|-------------|----------|-------------|----------|----------|
| EC01 | sort_only | asc | - | add_match | on_enter |
| EC02 | sort_only | desc | - | add_match | on_enter |
| EC03 | filter_only | - | equality | add_match | on_enter |
| EC04 | filter_only | - | equality | add_non_match | on_enter |
| EC05 | filter_only | - | range | change_to_match | on_enter |
| EC06 | filter_only | - | equality | change_to_non_match | on_leave |
| EC07 | sort_and_filter | asc | equality | add_match | on_enter |
| EC08 | sort_and_filter | desc | range | change_to_match | on_change |
| EC09 | sort_only | asc | - | change_to_match | on_change |
| EC10 | filter_only | - | range | add_non_match | on_leave |

#### Test Specifications

##### EC01: Edge sort ascending
- **Setup**: View with `edges = { posts = { sort = { field = "title", dir = "asc" } } }`; expand posts
- **Action**: Link posts with titles "C", "A", "B"
- **Assert**: `on_enter` fires in order A, B, C

##### EC02: Edge sort descending
- **Setup**: View with `edges = { posts = { sort = { field = "created_at", dir = "desc" } } }`
- **Action**: Link posts with created_at 1, 3, 2
- **Assert**: `on_enter` fires in order 3, 2, 1

##### EC03: Edge filter equality - matching
- **Setup**: View with `edges = { posts = { filters = {{ field = "published", op = "eq", value = true }} } }`
- **Action**: Link published post
- **Assert**: `on_enter` fires for published post

##### EC04: Edge filter equality - non-matching
- **Setup**: Same filter as EC03
- **Action**: Link unpublished post
- **Assert**: `on_enter` does NOT fire (post filtered out)

##### EC05: Edge filter range - property change to match
- **Setup**: View with `edges = { posts = { filters = {{ field = "views", op = "gt", value = 100 }} } }`; post with views=50 linked
- **Action**: Change post views to 150
- **Assert**: `on_enter` fires (post now matches filter)

##### EC06: Edge filter - property change to non-match
- **Setup**: Published post visible through equality filter
- **Action**: Change post.published to false
- **Assert**: `on_leave` fires (post no longer matches)

##### EC07: Edge sort and filter combined
- **Setup**: View with sort by title asc + filter published=true
- **Action**: Link 3 published posts with titles "Z", "A", "M"
- **Assert**: `on_enter` fires in order A, M, Z

##### EC08: Sort and range filter with property change
- **Setup**: View with sort desc + filter views > 50; post with views=100 visible
- **Action**: Change post views to 200
- **Assert**: `on_change` fires; post position may change in sorted order

##### EC09: Sort with property change affecting order
- **Setup**: Posts sorted by title asc; posts "A", "B", "C" visible
- **Action**: Change "A" title to "Z"
- **Assert**: `on_change` fires; item order is now B, C, Z

##### EC10: Range filter - add non-matching
- **Setup**: View with filter views > 100
- **Action**: Link post with views = 50
- **Assert**: No `on_enter` fires; post not visible in expansion

---

### C.3 View Navigation Tests (VN-*)

**Root Pattern**: Views support navigation methods `seek()` and `position_of()` for random access and position lookup within the virtual list.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| VN.1 Method | `seek`, `position_of` | Navigation method |
| VN.2 Target | `first`, `middle`, `last`, `beyond_end` | Position target |
| VN.3 View State | `roots_only`, `expanded`, `filtered` | Current view configuration |

#### 2-Wise Covering Array

| ID | Method | Target | View State |
|----|--------|--------|------------|
| VN01 | seek | first | roots_only |
| VN02 | seek | middle | roots_only |
| VN03 | seek | last | expanded |
| VN04 | seek | beyond_end | roots_only |
| VN05 | position_of | first | roots_only |
| VN06 | position_of | middle | filtered |

#### Test Specifications

##### VN01: Seek first position
- **Setup**: View with 5 root nodes
- **Action**: `view:seek(1)`
- **Assert**: Returns first node

##### VN02: Seek middle position
- **Setup**: View with 10 root nodes
- **Action**: `view:seek(5)`
- **Assert**: Returns 5th node by index order

##### VN03: Seek last with expansion
- **Setup**: View with 2 roots, first expanded with 3 children
- **Action**: `view:seek(5)` (2 roots + 3 children)
- **Assert**: Returns last child of first root

##### VN04: Seek beyond end
- **Setup**: View with 3 nodes
- **Action**: `view:seek(10)`
- **Assert**: Returns nil

##### VN05: Position of first node
- **Setup**: View with 5 nodes
- **Action**: `view:position_of(first_node._id)`
- **Assert**: Returns 1

##### VN06: Position of node in filtered view
- **Setup**: View with filter matching 3 of 5 nodes
- **Action**: `view:position_of(second_matching_node._id)`
- **Assert**: Returns 2 (position in filtered results)

---

### C.4 Item Method Tests (IM-*)

**Root Pattern**: Items returned from `view:items()` have convenience methods for expansion control: `toggle()`, `is_expanded()`, and `child_count()`.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| IM.1 Method | `toggle`, `is_expanded`, `child_count` | Item method |
| IM.2 Edge State | `collapsed`, `expanded`, `no_children` | Current expansion state |
| IM.3 Item Depth | `root`, `child` | Where item is in tree |

#### 2-Wise Covering Array

| ID | Method | Edge State | Depth |
|----|--------|------------|-------|
| IM01 | toggle | collapsed | root |
| IM02 | toggle | expanded | root |
| IM03 | is_expanded | collapsed | root |
| IM04 | is_expanded | expanded | child |
| IM05 | child_count | no_children | root |
| IM06 | child_count | expanded | child |

#### Test Specifications

##### IM01: Toggle collapsed edge
- **Setup**: Root item with collapsed posts edge
- **Action**: `item:toggle("posts")`
- **Assert**: Edge now expanded; `on_expand` fires

##### IM02: Toggle expanded edge
- **Setup**: Root item with expanded posts edge
- **Action**: `item:toggle("posts")`
- **Assert**: Edge now collapsed; `on_collapse` fires

##### IM03: is_expanded on collapsed
- **Setup**: Root item with collapsed edge
- **Action**: `item:is_expanded("posts")`
- **Assert**: Returns false

##### IM04: is_expanded on expanded child
- **Setup**: Nested expansion; child item with expanded comments
- **Action**: `item:is_expanded("comments")`
- **Assert**: Returns true

##### IM05: child_count with no children
- **Setup**: Root item with no linked posts
- **Action**: `item:child_count("posts")`
- **Assert**: Returns 0

##### IM06: child_count on expanded child
- **Setup**: Child item (post) with 5 comments linked
- **Action**: `item:child_count("comments")`
- **Assert**: Returns 5

---

### C.5 Graph Utility Tests (GU-*)

**Root Pattern**: The Graph API includes utility methods for direct property clearing, edge existence checking, and raw target/source access.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| GU.1 Method | `clear_prop`, `has_edge`, `targets`, `sources` | Utility method |
| GU.2 Data State | `exists`, `empty`, `deleted` | State of target data |
| GU.3 With Reverse | `yes`, `no` | Whether edge has reverse |

#### 2-Wise Covering Array

| ID | Method | Data State | With Reverse |
|----|--------|------------|--------------|
| GU01 | clear_prop | exists | - |
| GU02 | clear_prop | empty | - |
| GU03 | has_edge | exists | yes |
| GU04 | has_edge | empty | yes |
| GU05 | has_edge | exists | no |
| GU06 | targets | exists | yes |
| GU07 | targets | empty | yes |
| GU08 | sources | exists | yes |

#### Test Specifications

##### GU01: clear_prop clears existing property
- **Setup**: Node with `name = "Alice"`
- **Action**: `graph:clear_prop(node._id, "name")`
- **Assert**: `node.name:get() == nil`; `on_change` fires with old="Alice", new=nil

##### GU02: clear_prop on undefined property
- **Setup**: Node without `nickname` property
- **Action**: `graph:clear_prop(node._id, "nickname")`
- **Assert**: No error; no `on_change` fires (was already nil)

##### GU03: has_edge returns true for linked edge with reverse
- **Setup**: User linked to Post via `posts` edge (has reverse `author`)
- **Action**: `graph:has_edge(user._id, "posts", post._id)`
- **Assert**: Returns true

##### GU04: has_edge returns false for empty edge
- **Setup**: User with no posts linked
- **Action**: `graph:has_edge(user._id, "posts", some_post._id)`
- **Assert**: Returns false

##### GU05: has_edge on edge without reverse
- **Setup**: User linked to User2 via `friends` edge (no reverse)
- **Action**: `graph:has_edge(user._id, "friends", user2._id)`
- **Assert**: Returns true

##### GU06: targets returns linked node IDs
- **Setup**: User linked to 3 posts
- **Action**: `graph:targets(user._id, "posts")`
- **Assert**: Returns table with 3 post IDs

##### GU07: targets on empty edge returns empty table
- **Setup**: User with no posts
- **Action**: `graph:targets(user._id, "posts")`
- **Assert**: Returns empty table `{}`

##### GU08: sources returns reverse-linked node IDs
- **Setup**: Post linked to User via `author` (reverse of `posts`)
- **Action**: `graph:sources(post._id, "author")`
- **Assert**: Returns table with user ID

---

### C.6 Inline Edge Expansion Tests (IL-*)

**Root Pattern**: The `inline` flag affects depth calculation and visual flattening. It interacts with recursive edges, callbacks, and multi-parent structures.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| IL.1 Nesting | `single`, `nested_inline`, `mixed` | How inline is nested |
| IL.2 Combined With | `none`, `eager`, `recursive` | Other flags |
| IL.3 Callback | `on_enter`, `on_change`, `on_leave` | Which callback |

#### 2-Wise Covering Array

| ID | Nesting | Combined | Callback |
|----|---------|----------|----------|
| IL01 | single | none | on_enter |
| IL02 | single | eager | on_enter |
| IL03 | nested_inline | none | on_enter |
| IL04 | mixed | none | on_change |
| IL05 | single | recursive | on_enter |
| IL06 | nested_inline | eager | on_leave |

#### Test Specifications

##### IL01: Single inline edge - depth unchanged
- **Setup**: View with `edges = { posts = { inline = true } }`
- **Action**: Expand posts edge
- **Assert**: Child posts have `depth == 0` (same as parent)

##### IL02: Inline with eager
- **Setup**: View with `edges = { posts = { inline = true, eager = true } }`
- **Action**: Create view
- **Assert**: Posts auto-expanded with `depth == 0`

##### IL03: Nested inline edges
- **Setup**: `posts = { inline = true, edges = { comments = { inline = true } } }`
- **Action**: Expand posts, then comments
- **Assert**: Comments also have `depth == 0`

##### IL04: Mixed inline and non-inline
- **Setup**: `posts = { inline = true, edges = { comments = { inline = false } } }`
- **Action**: Expand both; change comment property
- **Assert**: Posts at `depth == 0`, comments at `depth == 1`; `on_change` fires with correct depth

##### IL05: Inline with recursive
- **Setup**: `children = { inline = true, recursive = true }` on category
- **Action**: Expand 3 levels
- **Assert**: All levels have `depth == 0`

##### IL06: Nested inline collapse
- **Setup**: Nested inline edges, expanded with eager
- **Action**: Collapse parent edge
- **Assert**: `on_leave` fires for all nested inline children

---

### Summary: Appendix C Test Matrix

| Section | Tests | Coverage | Feature Addressed |
|---------|-------|----------|-------------------|
| RE (Recursive Edge) | 12 | 3-wise | Self-referential edge expansion |
| EC (Edge Config) | 10 | 2-wise | Sort/filter on expanded edges |
| VN (View Navigation) | 6 | 2-wise | seek() and position_of() |
| IM (Item Methods) | 6 | 2-wise | toggle(), is_expanded(), child_count() |
| GU (Graph Utilities) | 8 | 2-wise | clear_prop(), has_edge(), targets(), sources() |
| IL (Inline Edges) | 6 | 2-wise | Inline flag interactions |

**Appendix C Test Specifications: 48**
**Total with All Appendices: 187**

---

## Updated Coverage Matrix

### Factor Coverage Summary (Updated)

| Subsystem | Factors | Levels | Tests | Coverage |
|-----------|---------|--------|-------|----------|
| Node/Property | 4 | 11 | 11 | 2-wise |
| Signal | 5 | 13 | 9 | 2-wise |
| EdgeHandle | 5 | 18 | 12 | 2-wise |
| Rollup | 6 | 23 | 17 | 3-wise |
| Index | 5 | 12 | 6 | 2-wise |
| View | 7 | 21 | 12 | 3-wise |
| View Methods | - | - | 9 | Exhaustive |
| Interactions | - | - | 6 | Key pairs |
| Edge Symmetry | 4 | 10 | 11 | 2-wise |
| Subscription Lifecycle | 5 | 14 | 9 | 2-wise |
| Initialization Race | 4 | 12 | 10 | 2-wise |
| Multi-Parent Paths | 4 | 10 | 9 | 2-wise |
| Raw/Proxy Boundary | 3 | 9 | 9 | 2-wise |
| Index Coupling | 3 | 9 | 9 | 2-wise |
| **Recursive Edge** | 5 | 14 | 12 | **3-wise** |
| **Edge Config Ext** | 5 | 12 | 10 | 2-wise |
| **View Navigation** | 3 | 9 | 6 | 2-wise |
| **Item Methods** | 3 | 7 | 6 | 2-wise |
| **Graph Utilities** | 3 | 7 | 8 | 2-wise |
| **Inline Edges** | 3 | 8 | 6 | 2-wise |

**Grand Total Test Specifications: 187**

---

## Appendix D: Planned Improvement Verification

This appendix defines test specifications to verify planned improvements to neograph-native. Each improvement addresses user feedback from production usage. Tests are structured to verify both the fix and non-regression of existing behavior.

### D.1 Edge Handle Identity Tests (EI-*)

**Root Pattern**: EdgeHandle objects are currently created per-access, causing subscription fragmentation. Subscriptions registered on one handle don't fire for mutations through another handle to the same logical edge. The fix caches EdgeHandle instances at the graph level by `(node_id, edge_name)`.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| EI.1 Access Pattern | `same_proxy`, `different_proxy`, `after_gc` | How handles are obtained |
| EI.2 Subscription Type | `onLink`, `onUnlink`, `each` | Type of edge subscription |
| EI.3 Mutation Source | `same_handle`, `different_handle`, `graph_direct` | Where mutation originates |
| EI.4 Handle Timing | `sub_first`, `mut_first` | Order of subscription vs mutation handle access |

#### 2-Wise Covering Array

| ID | Access Pattern | Subscription | Mutation Source | Timing |
|----|----------------|--------------|-----------------|--------|
| EI01 | same_proxy | onLink | same_handle | sub_first |
| EI02 | same_proxy | onLink | different_handle | sub_first |
| EI03 | different_proxy | onLink | different_handle | sub_first |
| EI04 | after_gc | onLink | different_handle | sub_first |
| EI05 | same_proxy | onUnlink | different_handle | mut_first |
| EI06 | different_proxy | each | same_handle | sub_first |
| EI07 | same_proxy | each | different_handle | sub_first |
| EI08 | after_gc | onUnlink | same_handle | sub_first |

#### Test Specifications

##### EI01: Same handle subscription and mutation (baseline)
- **Setup**: `handle = node.posts`; subscribe via `handle:onLink(cb)`
- **Action**: `handle:link(post)`
- **Assert**: Callback fires with post node
- **Validates**: Existing behavior preserved

##### EI02: Different handles from same proxy
- **Setup**: `handle1 = node.posts`; `handle2 = node.posts`; subscribe via `handle1:onLink(cb)`
- **Action**: `handle2:link(post)`
- **Assert**: Callback fires (handles share subscription state)
- **Validates**: Fix for Issue #1

##### EI03: Handles from different proxy accesses
- **Setup**: `proxy1 = graph:get(id)`; `proxy2 = graph:get(id)`; subscribe via `proxy1.posts:onLink(cb)`
- **Action**: `proxy2.posts:link(post)`
- **Assert**: Callback fires
- **Validates**: Cache survives proxy recreation

##### EI04: Handle survives garbage collection
- **Setup**: Subscribe via `graph:get(id).posts:onLink(cb)`; force GC
- **Action**: `graph:get(id).posts:link(post)` (new proxy)
- **Assert**: Callback fires
- **Validates**: Graph-level cache not affected by proxy GC

##### EI05: Unlink with mutation-first handle access
- **Setup**: Link post first; then `handle1 = node.posts`; `handle2 = node.posts`; subscribe via `handle2:onUnlink(cb)`
- **Action**: `handle1:unlink(post)`
- **Assert**: Callback fires
- **Validates**: Order of handle access doesn't matter

##### EI06: Each subscription with same handle mutation
- **Setup**: `handle = node.posts`; subscribe via `handle:each(effect)`
- **Action**: `handle:link(post)`
- **Assert**: Effect fires for new post
- **Validates**: each() works with identity fix

##### EI07: Each subscription with different handle mutation
- **Setup**: Subscribe via `node.posts:each(effect)`
- **Action**: Different handle access `node.posts:link(post)`
- **Assert**: Effect fires
- **Validates**: each() spans handle instances

##### EI08: Unlink after GC with same logical handle
- **Setup**: Link post; subscribe via handle; force GC
- **Action**: `graph:get(id).posts:unlink(post)`
- **Assert**: onUnlink callback fires
- **Validates**: Unlink events survive GC

---

### D.2 Reverse Edge Event Propagation Tests (RE-*)

**Root Pattern**: Bidirectional edges update both sides on link/unlink, but only fire events on the explicitly linked edge. The fix adds `_notify_edge_subs()` calls for the reverse edge after updating it.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| RE.1 Link Direction | `forward`, `reverse` | Which edge is explicitly linked |
| RE.2 Subscription Side | `forward`, `reverse`, `both` | Where subscriptions exist |
| RE.3 Event Type | `link`, `unlink` | Type of edge mutation |
| RE.4 Subscription Type | `onLink`, `onUnlink`, `each` | Type of subscription |

#### 2-Wise Covering Array

| ID | Link Dir | Sub Side | Event | Sub Type |
|----|----------|----------|-------|----------|
| RE01 | forward | forward | link | onLink |
| RE02 | forward | reverse | link | onLink |
| RE03 | reverse | forward | link | onLink |
| RE04 | reverse | reverse | link | onLink |
| RE05 | forward | both | link | onLink |
| RE06 | reverse | both | link | onLink |
| RE07 | forward | reverse | unlink | onUnlink |
| RE08 | reverse | forward | unlink | onUnlink |
| RE09 | forward | forward | link | each |
| RE10 | reverse | reverse | unlink | each |

#### Test Specifications

##### RE01: Forward link, forward subscription (baseline)
- **Setup**: Schema `User.posts -> Post` with reverse `author`; subscribe `user.posts:onLink(cb)`
- **Action**: `user.posts:link(post)`
- **Assert**: Callback fires with post
- **Validates**: Existing behavior preserved

##### RE02: Forward link, reverse subscription
- **Setup**: Subscribe `post.author:onLink(cb)`
- **Action**: `user.posts:link(post)`
- **Assert**: Callback fires with user
- **Validates**: Fix - reverse side gets notified

##### RE03: Reverse link, forward subscription
- **Setup**: Subscribe `user.posts:onLink(cb)`
- **Action**: `post.author:link(user)`
- **Assert**: Callback fires with post
- **Validates**: Fix - forward side gets notified

##### RE04: Reverse link, reverse subscription (baseline)
- **Setup**: Subscribe `post.author:onLink(cb)`
- **Action**: `post.author:link(user)`
- **Assert**: Callback fires with user
- **Validates**: Existing behavior preserved

##### RE05: Forward link, both sides subscribed
- **Setup**: Subscribe both `user.posts:onLink(cb1)` and `post.author:onLink(cb2)`
- **Action**: `user.posts:link(post)`
- **Assert**: Both callbacks fire (cb1 with post, cb2 with user)
- **Validates**: Both directions notified

##### RE06: Reverse link, both sides subscribed
- **Setup**: Subscribe both `user.posts:onLink(cb1)` and `post.author:onLink(cb2)`
- **Action**: `post.author:link(user)`
- **Assert**: Both callbacks fire
- **Validates**: Symmetry with RE05

##### RE07: Forward unlink, reverse subscription
- **Setup**: Link established; subscribe `post.author:onUnlink(cb)`
- **Action**: `user.posts:unlink(post)`
- **Assert**: Callback fires with user
- **Validates**: Unlink propagates to reverse

##### RE08: Reverse unlink, forward subscription
- **Setup**: Link established; subscribe `user.posts:onUnlink(cb)`
- **Action**: `post.author:unlink(user)`
- **Assert**: Callback fires with post
- **Validates**: Unlink propagates to forward

##### RE09: Forward link with each() subscription
- **Setup**: Subscribe `user.posts:each(effect)`
- **Action**: `user.posts:link(post)`
- **Assert**: Effect fires for post
- **Validates**: each() works with fix

##### RE10: Reverse unlink with each() cleanup
- **Setup**: Link established; subscribe `post.author:each(effect)` returning cleanup
- **Action**: `post.author:unlink(user)`
- **Assert**: Cleanup fires
- **Validates**: each() cleanup works with reverse events

---

### D.3 Previous Value in Callbacks Tests (PV-*)

**Root Pattern**: Signal `use()` callbacks only receive the new value. The fix passes old value as second argument for computing diffs, transitions, or conditional logic.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| PV.1 Callback Arity | `unary`, `binary` | Whether callback accepts old value |
| PV.2 Value Type | `primitive`, `nil_to_value`, `value_to_nil` | Type transition |
| PV.3 Change Count | `first`, `subsequent` | Which change in sequence |

#### 2-Wise Covering Array

| ID | Arity | Value Type | Change |
|----|-------|------------|--------|
| PV01 | unary | primitive | first |
| PV02 | binary | primitive | first |
| PV03 | binary | primitive | subsequent |
| PV04 | binary | nil_to_value | first |
| PV05 | binary | value_to_nil | first |
| PV06 | unary | value_to_nil | subsequent |

#### Test Specifications

##### PV01: Unary callback ignores old value (backward compat)
- **Setup**: `node.name:use(function(new) record(new) end)`
- **Action**: `node.name:set("Bob")`
- **Assert**: Callback receives "Bob"; no error from missing arg
- **Validates**: Backward compatibility

##### PV02: Binary callback receives old value on first change
- **Setup**: Node with `name = "Alice"`; `node.name:use(function(new, old) record(new, old) end)`
- **Action**: `node.name:set("Bob")`
- **Assert**: Callback receives ("Bob", "Alice")
- **Validates**: Old value passed correctly

##### PV03: Binary callback on subsequent changes
- **Setup**: Subscribe; change to "Bob"; change to "Charlie"
- **Action**: Observe second change callback
- **Assert**: Receives ("Charlie", "Bob")
- **Validates**: Old value updates correctly

##### PV04: Nil to value transition
- **Setup**: Node with `nickname = nil`; binary callback
- **Action**: `node.nickname:set("Al")`
- **Assert**: Receives ("Al", nil)
- **Validates**: Nil as old value works

##### PV05: Value to nil transition
- **Setup**: Node with `nickname = "Al"`; binary callback
- **Action**: `graph:update(id, { nickname = neo.NIL })`
- **Assert**: Receives (nil, "Al")
- **Validates**: Nil as new value works

##### PV06: Unary callback with value to nil (backward compat)
- **Setup**: Unary callback on property
- **Action**: Clear property to nil
- **Assert**: Callback receives nil; no error
- **Validates**: Existing code doesn't break

---

### D.4 Deep Equality Tests (DE-*)

**Root Pattern**: Table values trigger spurious updates when structurally equal but referentially different. The fix adds optional or automatic deep equality checking for table values.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| DE.1 Table Depth | `flat`, `nested`, `deeply_nested` | Structure complexity |
| DE.2 Equality | `equal`, `different_value`, `different_key` | Whether tables are equal |
| DE.3 Value Type | `primitives`, `mixed`, `with_nil` | Types in table |

#### 2-Wise Covering Array

| ID | Depth | Equality | Value Type |
|----|-------|----------|------------|
| DE01 | flat | equal | primitives |
| DE02 | flat | different_value | primitives |
| DE03 | flat | different_key | primitives |
| DE04 | nested | equal | primitives |
| DE05 | nested | different_value | mixed |
| DE06 | deeply_nested | equal | mixed |
| DE07 | flat | equal | with_nil |

#### Test Specifications

##### DE01: Flat equal tables - no spurious update
- **Setup**: `node.data:set({ a = 1, b = 2 })`; subscribe
- **Action**: `node.data:set({ a = 1, b = 2 })` (same content, new table)
- **Assert**: Callback does NOT fire
- **Validates**: Deep equality suppresses spurious update

##### DE02: Flat tables with different value
- **Setup**: `node.data:set({ a = 1 })`; subscribe
- **Action**: `node.data:set({ a = 2 })`
- **Assert**: Callback fires
- **Validates**: Real changes still detected

##### DE03: Flat tables with different key
- **Setup**: `node.data:set({ a = 1 })`; subscribe
- **Action**: `node.data:set({ b = 1 })`
- **Assert**: Callback fires
- **Validates**: Key differences detected

##### DE04: Nested equal tables
- **Setup**: `node.data:set({ inner = { x = 1 } })`; subscribe
- **Action**: `node.data:set({ inner = { x = 1 } })`
- **Assert**: Callback does NOT fire
- **Validates**: Deep comparison works recursively

##### DE05: Nested tables with inner difference
- **Setup**: `node.data:set({ inner = { x = 1 } })`; subscribe
- **Action**: `node.data:set({ inner = { x = 2 } })`
- **Assert**: Callback fires
- **Validates**: Nested differences detected

##### DE06: Deeply nested equal tables
- **Setup**: `node.data:set({ a = { b = { c = 1 } } })`; subscribe
- **Action**: `node.data:set({ a = { b = { c = 1 } } })`
- **Assert**: Callback does NOT fire
- **Validates**: Arbitrary depth works

##### DE07: Tables with nil values
- **Setup**: `node.data:set({ a = 1, b = nil })`; subscribe
- **Action**: `node.data:set({ a = 1 })`
- **Assert**: Callback does NOT fire (nil key equivalent to missing)
- **Validates**: Nil handling in comparison

---

### D.5 Multi-Subscriber Events Tests (MS-*)

**Root Pattern**: View events may only invoke the last registered callback. The fix ensures all registered callbacks fire in registration order.

#### Factors

| Factor | Levels | Description |
|--------|--------|-------------|
| MS.1 Subscriber Count | `2`, `3`, `many` | Number of subscribers |
| MS.2 Event Type | `enter`, `leave`, `change` | Which event |
| MS.3 Registration Method | `constructor`, `on_method`, `mixed` | How callbacks registered |
| MS.4 Unsubscribe | `none`, `middle`, `first` | Which subscriber unsubscribes |

#### 2-Wise Covering Array

| ID | Count | Event | Registration | Unsub |
|----|-------|-------|--------------|-------|
| MS01 | 2 | enter | on_method | none |
| MS02 | 3 | enter | on_method | none |
| MS03 | 2 | leave | on_method | middle |
| MS04 | 2 | change | constructor | none |
| MS05 | 3 | change | mixed | none |
| MS06 | many | enter | on_method | first |
| MS07 | 2 | enter | constructor | none |

#### Test Specifications

##### MS01: Two subscribers via on()
- **Setup**: `view:on("enter", cb1)`; `view:on("enter", cb2)`
- **Action**: Insert matching node
- **Assert**: Both cb1 and cb2 fire
- **Validates**: Multiple on() subscribers work

##### MS02: Three subscribers via on()
- **Setup**: Register 3 callbacks for "enter"
- **Action**: Insert matching node
- **Assert**: All 3 fire in registration order
- **Validates**: More than 2 works

##### MS03: Unsubscribe middle subscriber
- **Setup**: Register cb1, cb2, cb3; unsubscribe cb2
- **Action**: Delete node (triggers leave)
- **Assert**: cb1 and cb3 fire; cb2 does not
- **Validates**: Selective unsubscribe works

##### MS04: Constructor callback with on() addition
- **Setup**: Create view with `callbacks = { on_change = cb1 }`; add `view:on("change", cb2)`
- **Action**: Change property on visible node
- **Assert**: Both cb1 and cb2 fire
- **Validates**: Constructor + dynamic callbacks coexist

##### MS05: Mixed registration with three subscribers
- **Setup**: Constructor cb1; `on()` cb2; `on()` cb3
- **Action**: Change property
- **Assert**: All 3 fire
- **Validates**: Mixed registration works

##### MS06: Many subscribers with first unsubscribed
- **Setup**: Register 5 callbacks; unsubscribe first
- **Action**: Insert node
- **Assert**: Callbacks 2-5 fire; callback 1 does not
- **Validates**: First-unsubscribe edge case

##### MS07: Two constructor callbacks error
- **Setup**: Attempt to pass 2 callbacks for same event in constructor
- **Action**: Create view
- **Assert**: Only one callback accepted (or documented behavior)
- **Validates**: Constructor limitation documented

---

### D.6 Undefined Property Access Tests (UP-*)

**Root Pattern**: Accessing undefined properties returns Signal, making it impossible to distinguish schema properties from arbitrary access. Tests verify chosen fix option.

**Note**: Test specifications depend on chosen fix option:
- Option 1: Schema-defined properties only
- Option 2: Explicit `node:signal(name)` method
- Option 3: Reserve `_` prefix

#### Option 3 Tests (Reserve `_` prefix)

| ID | Property | Expected |
|----|----------|----------|
| UP01 | `node.name` (defined) | Returns Signal |
| UP02 | `node.undefined_prop` | Returns Signal (current behavior) |
| UP03 | `node._internal` | Returns nil |
| UP04 | `node._cache` | Returns nil |
| UP05 | `node.__index` | Returns nil |

#### Option 1 Tests (Schema-defined only)

| ID | Property | Expected |
|----|----------|----------|
| UP01 | `node.name` (in schema) | Returns Signal |
| UP02 | `node.undefined` (not in schema) | Returns nil |
| UP03 | `node._id` | Returns id (reserved) |
| UP04 | `node._type` | Returns type (reserved) |

---

### Summary: Appendix D Test Matrix

| Section | Tests | Coverage | Improvement Addressed |
|---------|-------|----------|----------------------|
| EI (Edge Handle Identity) | 8 | 2-wise | Issue #1 |
| RE (Reverse Edge Events) | 10 | 2-wise | Issue #13 |
| PV (Previous Value) | 6 | 2-wise | Issue #5 |
| DE (Deep Equality) | 7 | 2-wise | Issue #9 |
| MS (Multi-Subscriber) | 7 | 2-wise | Issue #2 |
| UP (Undefined Property) | 4-5 | Exhaustive | Issue #7 |

**Appendix D Test Specifications: 42-43**
**Grand Total with All Appendices: 229-230**

---

### Improvement Verification Checklist

Before marking an improvement as complete, verify:

| Improvement | Required Tests | Regression Tests |
|-------------|----------------|------------------|
| #1 Edge Handle Identity | EI01-EI08 pass | EH01-EH12 still pass |
| #2 Multi-Subscriber | MS01-MS07 pass | VW01-VW12 still pass |
| #5 Previous Value | PV01-PV06 pass | SG06-SG09 still pass |
| #7 Undefined Property | UP01-UP05 pass | NP*, SG* still pass |
| #9 Deep Equality | DE01-DE07 pass | SG03-SG05 still pass |
| #13 Reverse Edge Events | RE01-RE10 pass | EH01-EH04, ES01-ES11 still pass |

**Documentation-only improvements:**
- Issue #12 (Edge Iteration API): Verify `collect()` and `visible_total()` are documented
