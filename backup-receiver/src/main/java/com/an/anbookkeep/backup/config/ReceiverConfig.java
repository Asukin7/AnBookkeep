package com.an.anbookkeep.backup.config;

import java.nio.file.Path;

public record ReceiverConfig(String key, Path backupDirectory) {
    @Override
    public String toString() {
        return "ReceiverConfig[backupDirectory=" + backupDirectory + "]";
    }
}
