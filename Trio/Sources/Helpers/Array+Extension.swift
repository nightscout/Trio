extension Array where Element: Hashable {
    func removeDublicates() -> Self {
        var result = Self()
        for item in self {
            if !result.contains(item) {
                result.append(item)
            }
        }
        return result
    }
}
