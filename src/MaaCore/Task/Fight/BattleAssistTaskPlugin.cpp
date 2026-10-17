#include "BattleAssistTaskPlugin.h"

#include <array>
#include <chrono>
#include <vector>

#include "Config/TaskData.h"
#include "Controller/Controller.h"
#include "Utils/Logger.hpp"
#include "Vision/Battle/BattlefieldDetector.h"
#include "Vision/Battle/BattlefieldClassifier.h"

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
    m_last_auto_skill_use.clear();
    m_in_speedup = false;

    auto image = ctrler()->get_image();
    if (!check_in_battle(image, false)) {
        LogWarn << __FUNCTION__ << "battle is not active";
        return false;
    }
    if (m_auto_speed_up) {
        m_in_speedup = check_in_speedup(image);
        if (m_in_speedup) {
            LogInfo << __FUNCTION__ << "2x battle speed already enabled";
        }
        else if (speed_up()) {
            m_in_speedup = true;
            LogInfo << __FUNCTION__ << "enabled 2x battle speed";
        }
    }

    using clock = std::chrono::steady_clock;
    constexpr auto skill_scan_interval = std::chrono::milliseconds(1500);
    auto last_skill_scan = clock::now() - skill_scan_interval;

    while (!need_exit()) {
        image = ctrler()->get_image();
        if (!check_in_battle(image, false)) {
            break;
        }

        if (m_auto_use_skills && clock::now() - last_skill_scan >= skill_scan_interval) {
            use_all_ready_skills_on_battlefield(image);
            last_skill_scan = clock::now();
        }
        sleep(200);
    }

    return true;
}

bool asst::BattleAssistTaskPlugin::use_all_ready_skills_on_battlefield(const cv::Mat& image)
{
    BattlefieldDetector detector(image);
    detector.set_object_of_interest({ .operators = true });
    auto detector_result = detector.analyze();
    if (!detector_result || detector_result->operators.empty()) {
        return false;
    }

    struct ReadyOperator
    {
        Point click_point;
        Point classifier_base;
    };
    std::vector<ReadyOperator> ready_operators;
    ready_operators.reserve(detector_result->operators.size());

    for (const auto& oper : detector_result->operators) {
        const Point click_point {
            oper.rect.x + oper.rect.width / 2,
            oper.rect.y + oper.rect.height / 2,
        };
        const std::array<double, 3> base_ratios { 0.75, 1.0, 1.15 };
        for (double ratio : base_ratios) {
            const Point classifier_base {
                oper.rect.x + oper.rect.width / 2,
                oper.rect.y + static_cast<int>(oper.rect.height * ratio),
            };
            BattlefieldClassifier classifier(image);
            classifier.set_object_of_interest({ .skill_ready = true });
            classifier.set_base_point(classifier_base);
            auto result = classifier.analyze();
            if (result && result->skill_ready.ready) {
                ready_operators.emplace_back(ReadyOperator { click_point, classifier_base });
                break;
            }
        }
    }

    bool used = false;
    const auto now = std::chrono::steady_clock::now();
    constexpr auto same_tile_cooldown = std::chrono::seconds(5);
    for (const auto& [click_point, classifier_base] : ready_operators) {
        if (need_exit()) {
            break;
        }
        if (auto iter = m_last_auto_skill_use.find(click_point);
            iter != m_last_auto_skill_use.cend() && now - iter->second < same_tile_cooldown) {
            continue;
        }

        const int pre_delay = Task.get("BattleUseOper")->pre_delay;
        if (ctrler()->click(click_point) && sleep(pre_delay)
            && ProcessTask(this_task(), { "BattleUseSkillJustClick" }).run()) {
            used = true;
            m_last_auto_skill_use[click_point] = now;
            LogInfo << __FUNCTION__ << "used ready skill at" << click_point << "classifier base" << classifier_base;
        }
    }
    return used;
}
