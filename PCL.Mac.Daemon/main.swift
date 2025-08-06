//
//  main.swift
//  PCL.Mac.Daemon
//
//  Created by YiZhiMCQiu on 8/6/25.
//

import Foundation
import AppKit

func showDialog(message: String, title: String = "提示") {
    let script = "display dialog \"\(message)\" with title \"\(title)\" buttons {\"确定\"} default button \"确定\" with icon stop"
    let task = Process()
    task.launchPath = "/usr/bin/osascript"
    task.arguments = ["-e", script]
    task.launch()
    task.waitUntilExit()
}

func isProcessRunning(pid: pid_t) -> Bool {
    return kill(pid, 0) == 0
}

func onProcessExit() throws {
    log("进程已退出")
    let exitTime = Date()
    var isCrash = false
    var reportURL: URL!
    
    log("正在检查 DiagnosticReports")
    for _ in 0..<5 {
        if isCrash { break }
        // 获取所有诊断报告
        let reports = try FileManager.default.contentsOfDirectory(
            at: .libraryDirectory.appending(path: "Logs").appending(path: "DiagnosticReports"),
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.starts(with: "PCL.Mac") }
        
        for report in reports {
            if report.lastPathComponent.wholeMatch(of: /PCL\.Mac-\d{4}-\d{2}-\d{2}-\d{6}\.ips/) != nil {
                let resourceValues = try report.resourceValues(forKeys: [.creationDateKey])
                if let creationDate = resourceValues.creationDate,
                   abs(creationDate.timeIntervalSince(exitTime)) < 1 {
                    log("报告 \(report.lastPathComponent) 与检测到进程退出的时间间隔小于 1s，已确认崩溃")
                    reportURL = report
                    isCrash = true
                    break
                }
            }
        }
        Thread.sleep(forTimeInterval: 0.5)
    }
    
    if !isCrash {
        log("进程正常退出")
        return
    }
    let dateFormatter = DateFormatter()
    dateFormatter.dateFormat = "yyyyMMdd-HHmmSS"
    let exportDestination: URL = .desktopDirectory.appending(path: "PCL.Mac_崩溃报告_\(dateFormatter.string(from: exitTime))")
    try? FileManager.default.createDirectory(at: exportDestination, withIntermediateDirectories: true)
    
    // 拷贝日志与诊断报告
    try? FileManager.default.copyItem(
        at: .applicationSupportDirectory.appending(path: "PCL-Mac").appending(path: "Logs").appending(path: "app.log"),
        to: exportDestination.appending(path: "app.log")
    )
    try? FileManager.default.copyItem(at: reportURL, to: exportDestination.appending(path: "DiagnosticReport.ips"))
    
    log("日志拷贝完成")
    
    // 显示弹窗
    showDialog(message: "一个崩溃报告已被生成在你的桌面上，请压缩它并发送到用户群。", title: "PCL.Mac 已崩溃")
}

log("PCL.Mac.Daemon 已启动")

guard let application = NSWorkspace.shared.runningApplications
    .filter({ $0.bundleIdentifier == "io.github.pcl-communtiy.PCL-Mac" }).first else {
    warn("未识别到与 PCL.Mac Bundle ID 一致的进程")
    exit(1)
}

let pid = application.processIdentifier

log("父进程 PID: \(pid)")

while true {
    if !isProcessRunning(pid: pid) {
        do {
            try onProcessExit()
        } catch {
            err("无法处理退出: \(error.localizedDescription)")
        }
        break
    }
    Thread.sleep(forTimeInterval: 1)
}
