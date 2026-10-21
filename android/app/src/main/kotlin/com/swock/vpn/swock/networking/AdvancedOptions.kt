package com.swock.vpn.swock.networking

import org.json.JSONObject

/** User-selected performance options; every flag is off unless the profile enables it. */
data class AdvancedOptions(
    val adaptiveMtu: Boolean = false,
    val packetLossPrevention: Boolean = false,
    val callStability: Boolean = false,
    val lowLatency: Boolean = false,
    val stealthObfuscation: Boolean = false,
) {
    val needsLinkMonitor: Boolean get() = packetLossPrevention || callStability

    fun summary(): String = listOfNotNull(
        "stealth anti-DPI obfuscation".takeIf { stealthObfuscation },
        "adaptive MTU".takeIf { adaptiveMtu },
        "packet-loss prevention".takeIf { packetLossPrevention },
        "call stability".takeIf { callStability },
        "low latency".takeIf { lowLatency },
    ).joinToString(", ")

    companion object {
        fun from(profile: JSONObject): AdvancedOptions {
            val advanced = profile.optJSONObject("advanced") ?: return AdvancedOptions()
            return AdvancedOptions(
                adaptiveMtu = advanced.optBoolean("adaptiveMtu", false),
                packetLossPrevention = advanced.optBoolean("packetLossPrevention", false),
                callStability = advanced.optBoolean("callStability", false),
                lowLatency = advanced.optBoolean("lowLatency", false),
                stealthObfuscation = advanced.optBoolean("stealthObfuscation", false),
            )
        }
    }
}
