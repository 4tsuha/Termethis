package jp.yts.termethis

import android.app.Activity
import android.content.Context
import android.content.pm.ActivityInfo
import android.content.pm.FeatureInfo
import android.content.pm.PackageManager

internal enum class HardwareAccelerationMode {
    AUTOMATIC,
    VULKAN,
    DISABLED,
    ;

    val storageValue: String
        get() = name.lowercase()

    companion object {
        fun fromStorage(value: String?): HardwareAccelerationMode =
            entries.firstOrNull { it.storageValue == value } ?: AUTOMATIC
    }
}

internal data class VulkanCapabilities(
    val supported: Boolean,
    val version: String?,
    val hardwareLevel: Int?,
    val androidHardwareAccelerated: Boolean,
)

internal class VulkanRenderingController(private val context: Activity) {
    companion object {
        private const val PREFERENCES_NAME = "termethis_rendering"
        private const val MODE_KEY = "hardware_acceleration_mode"
        const val ENABLE_IMPELLER_ARGUMENT = "--enable-impeller=true"
        const val DISABLE_IMPELLER_ARGUMENT = "--enable-impeller=false"
        const val VULKAN_BACKEND_ARGUMENT = "--impeller-backend=vulkan"
    }

    private val preferences = context.getSharedPreferences(
        PREFERENCES_NAME,
        Context.MODE_PRIVATE,
    )

    fun selectedMode(): HardwareAccelerationMode =
        HardwareAccelerationMode.fromStorage(preferences.getString(MODE_KEY, null))

    fun setMode(mode: HardwareAccelerationMode) {
        preferences.edit().putString(MODE_KEY, mode.storageValue).apply()
    }

    fun capabilities(): VulkanCapabilities {
        val features = context.packageManager.systemAvailableFeatures.orEmpty()
        val versionFeature = features.firstOrNull {
            it.name == PackageManager.FEATURE_VULKAN_HARDWARE_VERSION
        }
        val levelFeature = features.firstOrNull {
            it.name == PackageManager.FEATURE_VULKAN_HARDWARE_LEVEL
        }
        val version = versionFeature?.version?.takeIf { it > 0 }
        return VulkanCapabilities(
            supported = versionFeature != null && version != null,
            version = version?.let(::formatVulkanVersion),
            hardwareLevel = levelFeature?.version?.takeIf { it >= 0 },
            androidHardwareAccelerated = isActivityHardwareAccelerated(),
        )
    }

    fun shouldEnableVulkan(
        mode: HardwareAccelerationMode,
        capabilities: VulkanCapabilities,
    ): Boolean = mode != HardwareAccelerationMode.DISABLED &&
        capabilities.supported &&
        capabilities.androidHardwareAccelerated

    @Suppress("DEPRECATION")
    private fun isActivityHardwareAccelerated(): Boolean = runCatching {
        val activityInfo = context.packageManager.getActivityInfo(
            context.componentName,
            PackageManager.GET_META_DATA,
        )
        activityInfo.flags and ActivityInfo.FLAG_HARDWARE_ACCELERATED != 0
    }.getOrDefault(false)

    private fun formatVulkanVersion(version: Int): String {
        val major = version ushr 22
        val minor = version ushr 12 and 0x3ff
        val patch = version and 0xfff
        return "$major.$minor.$patch"
    }
}
