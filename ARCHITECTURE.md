# Architecture

**Major considerations affecting architecture:**
* I have minimal time and money to spend on app maintenance over the the long term.
* We're not in this for fame or fortune. (i.e. not trying to go viral, not trying to earn revenue).
* Serve users well and don't break anything.

**From that, we have these key architecture principles:**
* No custom backend (Apple CloudKit okay). Less to maintain. No server costs, no forced upgrade cycles, less to monitor.
* No uses of undocumented API behaviors. Needs to survive multiple years of OS updates without incident. And needs to be easy to update code, with minimal deprecation issues.
* Latest Swift version
* Support only the latest iOS version.
* Native SwiftUI. No UIKit unless absolutely necessary.
* Minimize external libraries and frameworks. Prefer Apple-native APIs. If we must, prefer external packages that are actively maintained and widely used. 
* Minimize unusual coding practices. Stick to Apple-native and industry-standard implementations. Canonical coding idioms, best-practice SwiftUI, etc.

**More details in the agent-readable [tech-design-doc.md](docs/tech-design-doc.md).**
