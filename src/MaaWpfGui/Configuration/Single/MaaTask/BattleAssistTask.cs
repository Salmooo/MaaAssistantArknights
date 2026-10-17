// <copyright file="BattleAssistTask.cs" company="MaaAssistantArknights">
// Part of the MaaWpfGui project, maintained by the MaaAssistantArknights team (Maa Team)
// Copyright (C) 2021-2026 MaaAssistantArknights Contributors
//
// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU Affero General Public License v3.0 only as published by
// the Free Software Foundation, either version 3 of the License, or
// any later version.
//
// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY
// </copyright>

#nullable enable
using static MaaWpfGui.Main.AsstProxy;

namespace MaaWpfGui.Configuration.Single.MaaTask;

/// <summary>
/// 适用于所有理智作战的战斗辅助设置。
/// </summary>
public class BattleAssistTask : BaseTask
{
    public BattleAssistTask() => TaskType = TaskType.BattleAssist;

    /// <summary>
    /// Gets or sets a value indicating whether 自动使用场上所有就绪技能
    /// </summary>
    public bool AutoUseSkills { get; set; }

    /// <summary>
    /// Gets or sets a value indicating whether 战斗开始后自动切换到二倍速
    /// </summary>
    public bool AutoSpeedUp { get; set; }
}
