#include "BattleAssistTaskPlugin.h"

#include "Utils/Logger.hpp"

asst::BattleAssistTaskPlugin::BattleAssistTaskPlugin(
    const AsstCallback& callback,
    Assistant* inst,
    std::string_view task_chain) :
    AbstractTaskPlugin(callback, inst, task_chain),
    BattleHelper(inst)
{
}

void asst::BattleAssistTaskPlugin::set_options(bool auto_use_skills, bool auto_speed_up) noexcept
{
    m_auto_use_skills = auto_use_skills;
    m_auto_speed_up = auto_speed_up;
}

bool asst::BattleAssistTaskPlugin::verify(AsstMsg msg, const json::value& details) const
{
    if (!m_auto_use_skills && !m_auto_speed_up) {
        return false;
    }
    if (msg != AsstMsg::SubTaskStart || details.get("subtask", std::string()) != "ProcessTask") {
        return false;
    }

    const std::string task = details.get("details", "task", "");
    return task.ends_with("PRTS1") || task.ends_with("PRTS2") || task.ends_with("PRTS3");
}

bool asst::BattleAssistTaskPlugin::_run()
{
    LogTraceFunction;

    BattleHelper::clear();
    m_in_speedup = false;
    return run_battle_assist(m_auto_use_skills, m_auto_speed_up);
}
