/* Copyright (C) 2026  nikkov199525 */

/* This program is free software: you can redistribute it and/or modify */
/* it under the terms of the GNU Lesser General Public License as published by */
/* the Free Software Foundation, either version 3 of the License, or */
/* (at your option) any later version. */

package com.github.olga_yakovleva.rhvoice.android;

import android.content.Context;

import java.io.BufferedInputStream;
import java.io.BufferedOutputStream;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.nio.charset.StandardCharsets;
import java.util.zip.ZipEntry;
import java.util.zip.ZipInputStream;

final class EmbeddedData {
    private static final String ASSET_ARCHIVE = "embedded-data.zip";
    private static final String ASSET_VERSION = "embedded-data.version";
    private static final String VERSION_FILE = ".version";

    private EmbeddedData() {
    }

    static void install(Context context) throws IOException {
        String expectedVersion;
        try (InputStream input = context.getAssets().open(ASSET_VERSION)) {
            expectedVersion = readText(input).trim();
        }

        File targetDir = getRoot(context);
        File targetVersion = new File(targetDir, VERSION_FILE);
        if (targetVersion.isFile()) {
            try (InputStream input = new FileInputStream(targetVersion)) {
                if (expectedVersion.equals(readText(input).trim())
                        && new File(targetDir, "packages.json").isFile()) {
                    return;
                }
            }
        }

        File temporaryDir = context.getDir("embedded-data-tmp", Context.MODE_PRIVATE);
        if (!deleteContents(temporaryDir)) {
            throw new IOException("Unable to clean temporary embedded-data directory");
        }

        String temporaryPath = temporaryDir.getCanonicalPath() + File.separator;
        try (ZipInputStream archive = new ZipInputStream(
                new BufferedInputStream(context.getAssets().open(ASSET_ARCHIVE)))) {
            ZipEntry entry;
            byte[] buffer = new byte[8192];
            while ((entry = archive.getNextEntry()) != null) {
                File output = new File(temporaryDir, entry.getName());
                String outputPath = output.getCanonicalPath();
                if (!outputPath.startsWith(temporaryPath)) {
                    throw new IOException("Invalid path in embedded-data archive");
                }
                if (entry.isDirectory()) {
                    if (!output.isDirectory() && !output.mkdirs()) {
                        throw new IOException("Unable to create " + output);
                    }
                } else {
                    File parent = output.getParentFile();
                    if (!parent.isDirectory() && !parent.mkdirs()) {
                        throw new IOException("Unable to create " + parent);
                    }
                    try (BufferedOutputStream stream =
                                 new BufferedOutputStream(new FileOutputStream(output))) {
                        int count;
                        while ((count = archive.read(buffer)) != -1) {
                            stream.write(buffer, 0, count);
                        }
                    }
                }
                archive.closeEntry();
            }
        }

        try (FileOutputStream stream = new FileOutputStream(
                new File(temporaryDir, VERSION_FILE))) {
            stream.write(expectedVersion.getBytes(StandardCharsets.UTF_8));
        }

        if (!deleteRecursively(targetDir) || !temporaryDir.renameTo(targetDir)) {
            throw new IOException("Unable to activate embedded voice data");
        }
    }

    static String readPackageDirectory(Context context) throws IOException {
        try (InputStream input = new FileInputStream(
                new File(getRoot(context), "packages.json"))) {
            return readText(input);
        }
    }

    static String getPath(Context context, String type, String name) {
        File path = new File(new File(getRoot(context), type + "s"), name);
        return path.isDirectory() ? path.getAbsolutePath() : null;
    }

    private static File getRoot(Context context) {
        return context.getDir("embedded-data", Context.MODE_PRIVATE);
    }

    private static String readText(InputStream input) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[4096];
        int count;
        while ((count = input.read(buffer)) != -1) {
            output.write(buffer, 0, count);
        }
        return output.toString(StandardCharsets.UTF_8.name());
    }

    private static boolean deleteContents(File directory) {
        File[] children = directory.listFiles();
        if (children == null)
            return directory.isDirectory();
        for (File child : children) {
            if (!deleteRecursively(child))
                return false;
        }
        return true;
    }

    private static boolean deleteRecursively(File file) {
        if (!file.exists())
            return true;
        if (file.isDirectory() && !deleteContents(file))
            return false;
        return file.delete();
    }
}
