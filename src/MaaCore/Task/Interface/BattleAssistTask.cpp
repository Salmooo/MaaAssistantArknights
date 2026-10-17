#include "BattleAssistTask.h"

#include "Utils/Logger.hpp"

asst::BattleAssistTask::BattleAssistTask(const AsstCallback& callback, Assistant* inst) :
    InterfaceTask(callback, inst, TaskType),
    BattleHelper(inst)
{
}

bool asst::BattleAssistTask::set_params(const json::value& params)
{
    m_auto_use_skills = params.get("auto_use_skills", false);
    m_auto_speed_up = params.get("auto_speed_up", false);
    return true;
}

bool asst::BattleAssistTask::run()
{
    LogTraceFunction;

    if (!m_enable) {
        return true;
    }

    BattleHelper::clear();
    m_in_speedup = false;
    if (!check_in_battle(cv::Mat(), false)) {
        LogInfo << __FUNCTION__ << "no active battle, battle assist passed";
        return true;
    }
    return run_battle_assist(m_auto_use_skills, m_auto_speed_up);
}
