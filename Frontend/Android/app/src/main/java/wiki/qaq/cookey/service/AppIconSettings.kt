package wiki.qaq.cookey.service

import android.content.ComponentName
import android.content.Context
import android.content.pm.PackageManager
import androidx.annotation.DrawableRes
import wiki.qaq.cookey.R

object AppIconSettings {

    enum class Option(
        val storageValue: String,
        val title: String,
        val aliasName: String,
        @DrawableRes val iconRes: Int
    ) {
        DEFAULT(
            storageValue = "",
            title = "Default",
            aliasName = "LauncherDefault",
            iconRes = R.mipmap.ic_launcher
        ),
        BLUE(
            storageValue = "AppIcon_1",
            title = "Blue",
            aliasName = "LauncherBlue",
            iconRes = R.mipmap.ic_launcher_blue
        ),
        SILVER(
            storageValue = "AppIcon_2",
            title = "Silver",
            aliasName = "LauncherSilver",
            iconRes = R.mipmap.ic_launcher_silver
        );

        companion object {
            fun fromStoredValue(rawValue: String?): Option =
                entries.find { it.storageValue == (rawValue ?: "") } ?: DEFAULT
        }
    }

    fun getSelection(context: Context): Option {
        val packageManager = context.packageManager
        val detected = Option.entries.firstOrNull { option ->
            packageManager.getComponentEnabledSetting(componentName(context, option)) ==
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        }
        return detected ?: Option.fromStoredValue(AppSettings.getAppIcon(context))
    }

    fun synchronizeSelection(context: Context) {
        val selection = Option.fromStoredValue(AppSettings.getAppIcon(context))
        runCatching {
            updateLauncherAliases(context, selection)
        }.onFailure { error ->
            LogStore.error(
                context,
                LogCategory.APP,
                "Failed to synchronize app icon: ${error.message}"
            )
        }
    }

    fun applySelection(context: Context, requested: Option): Option {
        val current = getSelection(context)
        if (current == requested) {
            if (AppSettings.getAppIcon(context) != requested.storageValue) {
                AppSettings.setAppIcon(context, requested.storageValue)
            }
            return current
        }

        return runCatching {
            updateLauncherAliases(context, requested)
            AppSettings.setAppIcon(context, requested.storageValue)
            LogStore.info(
                context,
                LogCategory.APP,
                "Updated app icon selection to ${requested.title.lowercase()}"
            )
            requested
        }.getOrElse { error ->
            LogStore.error(
                context,
                LogCategory.APP,
                "Failed to update app icon selection: ${error.message}"
            )
            current
        }
    }

    private fun updateLauncherAliases(context: Context, selected: Option) {
        val packageManager = context.packageManager

        Option.entries.forEach { option ->
            val componentName = componentName(context, option)
            val desiredState = if (option == selected) {
                PackageManager.COMPONENT_ENABLED_STATE_ENABLED
            } else {
                PackageManager.COMPONENT_ENABLED_STATE_DISABLED
            }
            val currentState = packageManager.getComponentEnabledSetting(componentName)
            if (currentState != desiredState) {
                packageManager.setComponentEnabledSetting(
                    componentName,
                    desiredState,
                    PackageManager.DONT_KILL_APP
                )
            }
        }
    }

    private fun componentName(context: Context, option: Option): ComponentName =
        ComponentName(context, "${context.packageName}.${option.aliasName}")
}
