package com.example;

import com.fazecast.jSerialComm.SerialPort;
import javafx.application.Application;
import javafx.application.Platform;
import javafx.geometry.Insets;
import javafx.scene.Scene;
import javafx.scene.control.*;
import javafx.scene.layout.*;
import javafx.scene.text.Font;
import javafx.stage.Stage;

import java.io.OutputStream;
import java.nio.charset.StandardCharsets;

public class MatrixApp extends Application {

    // 全局串口对象
    private SerialPort activePort;
    private TextArea displayArea; // 结果显示区

    @Override
    public void start(Stage primaryStage) {
        // --- 根布局：水平分割 (左侧设置，右侧交互) ---
        BorderPane root = new BorderPane();

        root.setStyle(
                "-fx-background-image: url('/images/bg_tech.png'); " +
                        "-fx-background-size: cover; " +
                        "-fx-background-position: center center;"
        );

        // 1. 构建左侧设置栏
        VBox leftPanel = createLeftPanel();
        root.setLeft(leftPanel);

        // 2. 构建右侧主交互区
        VBox rightPanel = createRightPanel();
        root.setCenter(rightPanel);

        // --- 场景设置 ---
        Scene scene = new Scene(root, 900, 600); // 窗口大小
        primaryStage.setTitle("FPGA 矩阵运算上位机 (仿 UartAssist)");
        primaryStage.setScene(scene);
        primaryStage.show();

        // 关闭窗口时自动断开串口，释放资源
        primaryStage.setOnCloseRequest(event -> {
            if (activePort != null && activePort.isOpen()) {
                activePort.closePort();
            }
            Platform.exit();
            System.exit(0);
        });
    }

    // ==================================================================
    // 布局构建区
    // ==================================================================

    // 创建左侧面板：包含串口设置 + 业务参数设置
    private VBox createLeftPanel() {
        VBox vbox = new VBox(15); // 元素间距 15
        vbox.setPadding(new Insets(20));
        vbox.setPrefWidth(250);
        vbox.setStyle("-fx-background-color: #f4f4f4; -fx-border-color: #cccccc; -fx-border-width: 0 1 0 0;");

        // --- 模块 1: 串口连接 ---
        Label lblConn = new Label("串口设置");
        lblConn.setStyle("-fx-font-weight: bold; -fx-font-size: 14px;");

        ComboBox<String> portBox = new ComboBox<>();
        // 获取系统串口
        try {
            for (SerialPort p : SerialPort.getCommPorts()) {
                portBox.getItems().add(p.getSystemPortName());
            }
        } catch (Exception e) {
            portBox.setPromptText("未检测到串口");
        }
        if (!portBox.getItems().isEmpty()) portBox.getSelectionModel().select(0);

        ComboBox<Integer> baudBox = new ComboBox<>();
        baudBox.getItems().addAll(9600, 115200);
        baudBox.getSelectionModel().select(Integer.valueOf(50000000/1024)); // 默认选择一个常用的，或者手动改成 9600

        Button btnOpen = new Button("打开串口");
        btnOpen.setMaxWidth(Double.MAX_VALUE); // 按钮填满宽度
        btnOpen.setStyle("-fx-background-color: #4CAF50; -fx-text-fill: white; -fx-font-weight: bold;");

        // --- 模块 2: 矩阵参数 (作业要求 3.2) ---
        Separator sep = new Separator(); // 分割线
        Label lblConfig = new Label("参数配置");
        lblConfig.setStyle("-fx-font-weight: bold; -fx-font-size: 14px;");

        TextField txtMax = new TextField("2");
        txtMax.setPromptText("最大矩阵数 (x)");

        HBox rangeBox = new HBox(5);
        TextField txtMin = new TextField("0");
        TextField txtMaxVal = new TextField("9");
        txtMin.setPrefWidth(60); txtMaxVal.setPrefWidth(60);
        txtMin.setPromptText("Min"); txtMaxVal.setPromptText("Max");
        rangeBox.getChildren().addAll(txtMin, new Label("-"), txtMaxVal);

        Button btnConfig = new Button("下发配置");
        btnConfig.setMaxWidth(Double.MAX_VALUE);

        // --- 事件逻辑：打开串口 ---
        btnOpen.setOnAction(e -> {
            if (activePort != null && activePort.isOpen()) {
                activePort.closePort();
                btnOpen.setText("打开串口");
                btnOpen.setStyle("-fx-background-color: #4CAF50; -fx-text-fill: white; -fx-font-weight: bold;");
                activePort = null;
            } else {
                String portName = portBox.getValue();
                if (portName == null) {
                    showAlert("错误", "请先选择一个串口！");
                    return;
                }
                activePort = SerialPort.getCommPort(portName);
                // 如果你的波特率是下拉框选的：
                if (baudBox.getValue() != null) {
                    activePort.setBaudRate(baudBox.getValue());
                } else {
                    activePort.setBaudRate(9600); // 默认
                }

                if (activePort.openPort()) {
                    btnOpen.setText("关闭串口");
                    btnOpen.setStyle("-fx-background-color: #f44336; -fx-text-fill: white; -fx-font-weight: bold;");
                    startReadingService(); // 启动读取线程
                } else {
                    showAlert("错误", "无法打开串口，可能被占用！");
                }
            }
        });

        // --- 事件逻辑：下发配置 ---
        btnConfig.setOnAction(e -> {
            // 发送指令：CFG [MAX] [MIN] [MAX_VAL]
            // 注意：这里需要根据你FPGA实际解析的指令格式来写
            // 假设格式为： "SET_CFG 2 0 9\n"
            String cmd = String.format("SET_CFG %s %s %s\n",
                    txtMax.getText(), txtMin.getText(), txtMaxVal.getText());
            sendData(cmd);
        });

        vbox.getChildren().addAll(
                lblConn, new Label("端口:"), portBox, new Label("波特率:"), baudBox, btnOpen,
                sep,
                lblConfig, new Label("最大矩阵数:"), txtMax, new Label("数值范围:"), rangeBox, btnConfig
        );
        return vbox;
    }

    // 创建右侧面板：结果显示 + 矩阵输入
    private VBox createRightPanel() {
        VBox vbox = new VBox(10);
        vbox.setPadding(new Insets(20));

        // --- 上半部分：显示屏 ---
        Label lblDisplay = new Label("接收窗口 (运算结果)");
        lblDisplay.setStyle("-fx-font-weight: bold;");

        displayArea = new TextArea();
        displayArea.setEditable(false);
        // [关键] 设置等宽字体，保证矩阵对齐。如果没有 Consolas，系统会自动回退到 Monospaced
        displayArea.setFont(Font.font("Consolas", 14));
        displayArea.setStyle("-fx-control-inner-background: black; -fx-text-fill: #00ff00; -fx-font-family: 'Consolas', 'Monospaced';");
        VBox.setVgrow(displayArea, Priority.ALWAYS); // 自动填充剩余空间

        // --- 下半部分：操作区 ---
        Label lblInput = new Label("矩阵输入区");
        lblInput.setStyle("-fx-font-weight: bold;");

        HBox inputBox = new HBox(10);
        inputBox.setPrefHeight(150);

        TextArea inputA = new TextArea("1 2\n3 4");
        inputA.setPromptText("矩阵 A 数据...");

        TextArea inputB = new TextArea("5 6\n7 8");
        inputB.setPromptText("矩阵 B 数据...");

        // 按钮组
        VBox btnGroup = new VBox(10);
        btnGroup.setMinWidth(100);
        Button btnAdd = new Button("加法 (+)");
        Button btnMul = new Button("乘法 (*)");
        Button btnClear = new Button("清空日志");

        btnAdd.setMaxWidth(Double.MAX_VALUE);
        btnMul.setMaxWidth(Double.MAX_VALUE);
        btnClear.setMaxWidth(Double.MAX_VALUE);

        // 按钮事件
        btnAdd.setOnAction(e -> sendMatrixOp("ADD", inputA.getText(), inputB.getText()));
        btnMul.setOnAction(e -> sendMatrixOp("MUL", inputA.getText(), inputB.getText()));
        btnClear.setOnAction(e -> displayArea.clear());

        btnGroup.getChildren().addAll(btnAdd, btnMul, btnClear);
        inputBox.getChildren().addAll(inputA, btnGroup, inputB);
        // 让输入框自动拉伸
        HBox.setHgrow(inputA, Priority.ALWAYS);
        HBox.setHgrow(inputB, Priority.ALWAYS);

        vbox.getChildren().addAll(lblDisplay, displayArea, lblInput, inputBox);
        return vbox;
    }

    // ==================================================================
    // 逻辑功能区
    // ==================================================================

    // 发送数据
    private void sendData(String data) {
        if (activePort == null || !activePort.isOpen()) {
            showAlert("警告", "串口未打开，无法发送！");
            return;
        }
        try {
            OutputStream out = activePort.getOutputStream();
            out.write(data.getBytes(StandardCharsets.UTF_8));
            out.flush();
            // 在显示屏回显发送内容（可选，用于调试）
            Platform.runLater(() -> displayArea.appendText("[TX] " + data.trim() + "\n"));
        } catch (Exception e) {
            e.printStackTrace();
            showAlert("错误", "发送失败: " + e.getMessage());
        }
    }

    // 组装矩阵协议并发送
    private void sendMatrixOp(String opCode, String matA, String matB) {
        // 这里根据你之前的 Verilog 设计，假设协议是简单的文本行发送
        // 实际发送前可能需要对 matA 的换行符进行处理，确保 FPGA 能识别
        StringBuilder sb = new StringBuilder();

        // 示例协议： OP_CODE \n MAT_A_DATA \n MAT_B_DATA
        // 你需要根据 FPGA 的状态机来调整这里发送的顺序
        sb.append("OP_").append(opCode).append("\n");
        sb.append(matA.replace("\n", " ")).append("\n"); // 把换行变成空格发送
        sb.append(matB.replace("\n", " ")).append("\n");

        sendData(sb.toString());
    }

    // 开启后台线程读取数据
    private void startReadingService() {
        Thread thread = new Thread(() -> {
            byte[] buffer = new byte[1024];
            while (activePort != null && activePort.isOpen()) {
                if (activePort.bytesAvailable() > 0) {
                    int len = activePort.readBytes(buffer, buffer.length);
                    if (len > 0) {
                        String received = new String(buffer, 0, len, StandardCharsets.UTF_8);
                        // [关键] UI更新必须在主线程
                        Platform.runLater(() -> displayArea.appendText(received));
                    }
                }
                try { Thread.sleep(20); } catch (Exception e) {}
            }
        });
        thread.setDaemon(true);
        thread.start();
    }

    // 弹窗助手
    private void showAlert(String title, String content) {
        Alert alert = new Alert(Alert.AlertType.INFORMATION);
        alert.setTitle(title);
        alert.setHeaderText(null);
        alert.setContentText(content);
        alert.showAndWait();
    }

    public static void main(String[] args) {
        launch(args);
    }
}