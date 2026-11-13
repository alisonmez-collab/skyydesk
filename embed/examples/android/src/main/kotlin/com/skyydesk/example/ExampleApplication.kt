package com.skyydesk.example

import android.app.Application
import com.skyydesk.embed.SkyyDesk

class ExampleApplication : Application() {
    override fun onCreate() {
        super.onCreate()
        SkyyDesk.init(this)
    }
}
