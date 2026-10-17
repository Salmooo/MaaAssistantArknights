#pragma once

#include <chrono>
#include <map>
#include <string>

#include "Task/AbstractTaskPlugin.h"
#include "Task/BattleHelper.h"

namespace asst
{
class BattleAssistTaskPlugin final : public AbstractTaskPlugin, private BattleHelper
{
public:
    BattleAssistTaskPlugin(const AsstCallback& callback, Assistant* inst, std::string_view task_chain);
    virtual ~BattleAssistTaskPlugin() override = default;

    void set_options(bool auto_use_skills, bool auto_speed_up) noexcept;
    bool set_fight_stage(const std::string& stage);

    virtual bool verify(AsstMsg msg, const json::value& details) const override;

protected:
    virtual bool _run() override;
    virtual AbstractTask& this_task() override { return *this; }

private:
    bool use_all_ready_skills_on_battlefield(const cv::Mat& image);

    bool m_auto_use_skills = false;
    bool m_auto_speed_up = false;
    bool m_stage_supported = false;
    std::map<Point, std::chrono::steady_clock::time_point> m_last_auto_skill_use;
};
}
