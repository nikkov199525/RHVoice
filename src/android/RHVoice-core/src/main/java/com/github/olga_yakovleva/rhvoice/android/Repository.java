/* Copyright (C) 2021, 2022  Olga Yakovleva <olga@rhvoice.org> */

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

import android.content.Context;
import android.util.Log;

import androidx.annotation.MainThread;
import androidx.lifecycle.LiveData;
import androidx.lifecycle.MutableLiveData;

import com.google.common.util.concurrent.Futures;
import com.google.common.util.concurrent.ListenableFuture;
import com.squareup.moshi.JsonAdapter;
import com.squareup.moshi.Moshi;

import java.io.IOException;

final class Repository {
    private static final String TAG = "RHVoice.Repository";
    private static volatile Repository instance;
    private final Context context;
    private volatile PackageDirectory pkgDir;
    private final MutableLiveData<PackageDirectory> pkgDirLiveData;
    private final JsonAdapter<PackageDirectory> jsonAdapter;

    @MainThread
    private Repository(Context context) {
        this.context = context.getApplicationContext();
        pkgDirLiveData = new MutableLiveData<>();
        jsonAdapter = new Moshi.Builder().build()
                .adapter(PackageDirectory.class)
                .nonNull();
        initialLoad();
    }

    public static Repository get() {
        return instance;
    }

    @MainThread
    public static void initialize(Context context) {
        if (instance != null)
            throw new IllegalStateException();
        instance = new Repository(context);
    }

    public PackageDirectory getPackageDirectory() {
        return pkgDir;
    }

    public DataManager createDataManager() {
        DataManager dm = new DataManager();
        dm.setPackageDirectory(getPackageDirectory());
        return dm;
    }

    public LiveData<PackageDirectory> getPackageDirectoryLiveData() {
        return pkgDirLiveData;
    }

    private boolean parse(String str) throws IOException {
        if (str == null)
            return false;
        final PackageDirectory dir = jsonAdapter.fromJson(str);
        dir.index();
        pkgDir = dir;
        pkgDirLiveData.postValue(dir);
        return true;
    }

    private void initialLoad() {
        try {
            parse(EmbeddedData.readPackageDirectory(context));
        } catch (Exception e) {
            if (BuildConfig.DEBUG)
                Log.e(TAG, "Error on initial load", e);
        }
    }

    public ListenableFuture<Boolean> refresh() {
        return Futures.immediateFuture(true);
    }

    public ListenableFuture<Boolean> check() {
        return Futures.immediateFuture(true);
    }
}
