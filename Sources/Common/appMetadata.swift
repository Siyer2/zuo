public let stableZuoAppId: String = "com.syamiyer.zuo"
#if DEBUG
    public let zuoAppId: String = "com.syamiyer.zuo.debug"
    public let zuoAppName: String = "Zuo-Debug"
#else
    public let zuoAppId: String = stableZuoAppId
    public let zuoAppName: String = "Zuo"
#endif
