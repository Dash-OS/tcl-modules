proc ensembled {} {
  uplevel 1 {
    namespace ensemble create
    namespace export {[a-z]*}
  }
}
