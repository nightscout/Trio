# Developer Strategies

The key words “MUST”, “MUST NOT”, “REQUIRED”, “SHALL”, “SHALL NOT”, “SHOULD”, “SHOULD NOT”, “RECOMMENDED”, “MAY”, and “OPTIONAL” in this document are to be interpreted as described in [RFC 2119](https://www.ietf.org/rfc/rfc2119.txt).


## Branch Naming Strategy

Branches should be created with ... TBC

## Branching Strategies

 There are 3 main types of branches:

[Main](https://github.com/nightscout/Open-iAPS/tree/main) - Used for releasing stable, well-tested versions of Open-iAPS.

[Dev](https://github.com/nightscout/Open-iAPS/tree/dev) - Used as a final-step before merging to main. Use this branch to checkout feature / bug branches.

Feature - Used for developing new features or bug fixes. 

### Creating a Feature Branch

When checking out a new feature branch, you should do so directly from [dev](https://github.com/nightscout/Open-iAPS/tree/dev)

## Merging Strategies

### Merging to Dev
Merging to Dev requires a PR. See `Pull Request Definitions` below.

We recommend using a "squash and merge" strategy for feature branches. This keeps the main branch history clean and easier to understand.

### Merging to your own development branch

You can merge directly to your own feature branch.

## Committing Code

When commiting code to your branch, the scope shall be limited to the work identified in the ticket. See [Atomic Commits](https://rajrock38.medium.com/what-are-atomic-commits-96d4daa21fd4)

Each commit shall contain _only_ code relating to the feature or bug fix, nothing else. This helps maintain the integrity of the code base, and helps with identifying commits easier, should a roll-back be needed.

## Commit Messages

*** Notes ***
Should we add a git hook to prepend the ticket number to the commit message to help identify it at a later stage?

Commit messages shall follow the [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/#summary) strategy.


## Pull Request Definitions

PRs must include:
* A link to the issue ticket
* Tests completed
* A brief description of the issue

## Pull Request Definitions

* Before merging your PR, it _must_ be approved by at least 2 developers below:

| Name      | GitHub Username   | Email    |
| --------- | ---------         | -------- |
John Doe    | JDOE              | jdoe@iaps.com


PRs should try to include:
* Any notes worth including, not immediately obvious from the description
* Links to any documentation, or research related to the feature / bug fix.

## Ticket Definitions 
Tickets must include the following:
* User story?? -- what other _story_ elements should we include here.
* Acceptance Criteria

Tickets _should_ try to include the following, when appropriate:
* Developer Notes

## Definition of Done

A piece of work (a feature, or bug-fix etc.) is considered "done" when it meets the following criteria:
* The track of work must be assigned to a ticket.
* The acceptance criteria is met.
* The branch build has successfully completed.
* All unit tests have passes
* All automated test suites have passed
* If necessary, the documentation has been updated.



