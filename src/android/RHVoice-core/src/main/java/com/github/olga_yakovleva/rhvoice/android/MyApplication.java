/* Copyright (C) 2018, 2021  Olga Yakovleva <olga@rhvoice.org> */

/* This program is free software: you can redistribute it and/or modify */
/* it under the terms of the GNU Lesser General Public License as published by */
/* the Free Software Foundation, either version 3 of the License, or */
/* (at your option) any later version. */

/* This program is distributed in the hope that it will be useful, */
/* but WITHOUT ANY WARRANTY; without even the implied warranty of */
/* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the */
/* GNU Lesser General Public License for more details. */

/* You should have received a copy of the GNU Lesser General Public License */
/* along with this program.  If not, see <https://www.gnu.org/licenses/>. */

package com.github.olga_yakovleva.rhvoice.android;

import androidx.multidex.MultiDexApplication;

import android.util.Log;

import com.google.android.material.color.DynamicColors;

public final class MyApplication extends MultiDexApplication {
    private static final String TAG = "RHVoice.MyApplication";

    @Override
    public void onCreate() {
        super.onCreate();
        DynamicColors.applyToActivitiesIfAvailable(this);
        try {
            EmbeddedData.install(this);
        } catch (java.io.IOException e) {
            Log.e(TAG, "Unable to install embedded voice data", e);
            throw new IllegalStateException(e);
        }
        Repository.initialize(this);
    }
}
