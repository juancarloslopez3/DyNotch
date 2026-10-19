#!/usr/bin/env swift
// Sends a debug command to a running Debug build of DyNotch.
// Usage: swift scripts/notch.swift open home | close | hud volume | caps | dismiss | guide accessibility | tour hud
import Foundation

let command = CommandLine.arguments.dropFirst().joined(separator: " ")
DistributedNotificationCenter.default().postNotificationName(
    Notification.Name("app.dynotch.debug"),
    object: command,
    userInfo: nil,
    deliverImmediately: true
)
