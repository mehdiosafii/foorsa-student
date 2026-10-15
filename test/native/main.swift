// Compile together with the actual vendored policy, then execute.
func check(_ expected: Bool, _ frame: Bool, _ scheme: String, _ host: String, _ port: Int) {
    precondition(FoorsaBridgePolicy.allows(isMainFrame: frame, scheme: scheme, host: host, port: port) == expected)
}
check(true, true, "https", "student.foorsa.ma", 0)
check(true, true, "https", "student.foorsa.ma", 443)
check(false, false, "https", "student.foorsa.ma", 443)
check(false, true, "http", "student.foorsa.ma", 80)
check(false, true, "https", "student.foorsa.ma", 8443)
for host in ["evil.vercel.app", "evil.supabase.co", "csca.foorsa.ma", "hsk.foorsa.ma", "www.youtube.com", "student.foorsa.ma.evil.com", ""] {
    check(false, true, "https", host, 443)
    check(false, false, "https", host, 443)
}
print("Foorsa native main-frame/origin policy checks passed")
