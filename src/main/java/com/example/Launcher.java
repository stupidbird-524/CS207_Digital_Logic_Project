package com.example;

public class Launcher {
    public static void main(String[] args) {
        // 这里调用 MatrixApp 的 main 方法来启动
        // 就像是找个“中间人”来启动它，避开 JDK 的检查
        MatrixApp.main(args);
    }
}