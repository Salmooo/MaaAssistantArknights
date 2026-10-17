// <copyright file="BattleAssistSettingsUserControlModel.cs" company="MaaAssistantArknights">
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
using System.Collections.Generic;
using System.Linq;
using MaaWpfGui.Configuration.Single.MaaTask;
using MaaWpfGui.Helper;
using MaaWpfGui.Main;
using MaaWpfGui.Models.AsstTasks;
using MaaWpfGui.ViewModels;

namespace MaaWpfGui.ViewModels.UserControl.TaskQueue;

/// <summary>
/// 适用于所有理智作战的战斗辅助设置。
/// </summary>
public class BattleAssistSettingsUserControlModel : TaskSettingsViewModel, BattleAssistSettingsUserControlModel.ISerialize
{
    static BattleAssistSettingsUserControlModel()
    {
        Instance = new();
    }

    private BattleAssistSettingsUserControlModel()
    {
    }

    public static BattleAssistSettingsUserControlModel Instance { get; }

    /// <summary>
    /// Gets or sets a value indicating whether 自动使用场上所有就绪技能。
    /// </summary>
    public bool AutoUseSkills
    {
        get => GetTaskConfig<BattleAssistTask>().AutoUseSkills;
        set => SetTaskConfig<BattleAssistTask>(t => t.AutoUseSkills == value, t => t.AutoUseSkills = value);
    }

    /// <summary>
    /// Gets or sets a value indicating whether 战斗开始后自动切换到二倍速。
    /// </summary>
    public bool AutoSpeedUp
    {
        get => GetTaskConfig<BattleAssistTask>().AutoSpeedUp;
        set => SetTaskConfig<BattleAssistTask>(t => t.AutoSpeedUp == value, t => t.AutoSpeedUp = value);
    }

    public override void RefreshUI(BaseTask baseTask)
    {
        if (baseTask is BattleAssistTask)
        {
            Refresh();
        }
    }

    public override (bool? IsSuccess, IEnumerable<int> TaskId) SerializeTask(BaseTask? baseTask, int? taskId = null) =>
        (this as ISerialize).Serialize(baseTask, taskId);

    private interface ISerialize : ITaskQueueModelSerialize
    {
        (bool? IsSuccess, IEnumerable<int> TaskId) ITaskQueueModelSerialize.Serialize(BaseTask? baseTask, int? taskId)
        {
            if (baseTask is not BattleAssistTask assist)
            {
                return (null, []);
            }

            if (taskId is int existingId and > 0)
            {
                return (true, [existingId]);
            }

            var task = new AsstBattleAssistTask {
                AutoUseSkills = assist.AutoUseSkills,
                AutoSpeedUp = assist.AutoSpeedUp,
            };
            var appendResult = Instances.AsstProxy.AsstAppendTaskWithEncoding(AsstProxy.TaskType.BattleAssist, task);
            return FromSingle(appendResult);
        }
    }
}
