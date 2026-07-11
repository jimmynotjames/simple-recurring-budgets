# Architecture

**Major considerations affecting architecture:**
* I have minimal time and money to spend on app maintenance over the the long term.
* We're not in this for fame or fortune. (i.e. not trying to go viral, not trying to earn revenue).
* Serve users well and don't break anything over the long term.
* Write commercial-grade code, as if this were an enterprise app, for sake of professional development, but don't overdo it. (e.g. we have lots of tests and clean modularity, but we only do @MainActor isolation instead of fussing with background threads.)

**From that, we have these key architecture principles:**

* Clean separation of concerns in code base to support testability and modularity. I.e. clean database layer, domain layer that's SwiftUI-free, use of View Model patterns when appropriate.
* No custom backend (Apple CloudKit okay). Less to maintain. No server costs, no forced upgrade cycles, less to monitor.
* No uses of undocumented API behaviors. Needs to survive multiple years of OS updates without incident. And needs to be easy to update code after years away from this code base, with minimal deprecation issues.
* Support only the latest iOS version.
* Latest Swift version and latest Apple frameworks, idioms, etc.
* Native SwiftUI. No UIKit unless absolutely necessary.
* Minimize external libraries and frameworks. Prefer Apple-native APIs. If we must, prefer external packages that are actively maintained and widely used. 
* Minimize unusual coding practices. Stick to Apple-native and industry-standard implementations. Canonical coding idioms, best-practice SwiftUI, etc.

**More details in the agent-readable [tech-design-doc.md](docs/tech-design-doc.md).**
