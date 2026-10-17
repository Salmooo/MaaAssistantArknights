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
    if (!m_auto_use_skills && !m_auto_speed_up) {
        return true;
    }

    BattleHelper::clear();
    m_in_speedup = false;
    LogInfo << __FUNCTION__ << "waiting for personal battle";
    while (!need_exit()) {
        if (check_in_battle(cv::Mat(), false)) {
            run_battle_assist(m_auto_use_skills, m_auto_speed_up);
            BattleHelper::clear();
            m_in_speedup = false;
            LogInfo << __FUNCTION__ << "battle finished, waiting for next battle";
        }
        else {
            sleep(500);
        }
    }
    return true;
}
