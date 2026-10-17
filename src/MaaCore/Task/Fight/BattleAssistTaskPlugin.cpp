#include "BattleAssistTaskPlugin.h"

#include <chrono>
#include <vector>

#include "Config/TaskData.h"
#include "Controller/Controller.h"
#include "Utils/Logger.hpp"
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

bool asst::BattleAssistTaskPlugin::set_fight_stage(const std::string& stage)
{
    m_stage_supported = false;
    if (stage.empty()) {
        LogWarn << __FUNCTION__ << "cannot resolve tile map without a concrete stage";
        return false;
    }
    if (!BattleHelper::set_stage_name(stage) || !calc_tiles_info(stage)) {
        LogWarn << __FUNCTION__ << "unsupported battle assist stage" << stage;
        return false;
    }
    m_stage_supported = true;
    return true;
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
    if (!m_stage_name.empty()) {
        m_stage_supported = calc_tiles_info(m_stage_name);
    }

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

        if (m_auto_use_skills && m_stage_supported && clock::now() - last_skill_scan >= skill_scan_interval) {
            use_all_ready_skills_on_battlefield(image);
            last_skill_scan = clock::now();
        }
        sleep(200);
    }

    return true;
}

bool asst::BattleAssistTaskPlugin::use_all_ready_skills_on_battlefield(const cv::Mat& image)
{
    std::vector<Point> ready_locations;
    ready_locations.reserve(m_normal_tile_info.size());

    const Rect image_rect { 0, 0, image.cols, image.rows };
    for (const auto& [location, tile] : m_normal_tile_info) {
        if (!image_rect.include(tile.pos)) {
            continue;
        }

        BattlefieldClassifier classifier(image);
        classifier.set_object_of_interest({ .skill_ready = true });
        classifier.set_base_point(tile.pos);
        if (auto result = classifier.analyze(); result && result->skill_ready.ready) {
            ready_locations.emplace_back(location);
        }
    }

    bool used = false;
    const auto now = std::chrono::steady_clock::now();
    constexpr auto same_tile_cooldown = std::chrono::seconds(5);
    for (const Point& location : ready_locations) {
        if (need_exit()) {
            break;
        }
        if (auto iter = m_last_auto_skill_use.find(location);
            iter != m_last_auto_skill_use.cend() && now - iter->second < same_tile_cooldown) {
            continue;
        }
        if (use_skill(location, 0)) {
            used = true;
            m_last_auto_skill_use[location] = now;
            LogInfo << __FUNCTION__ << "used ready skill at" << location;
        }
    }
    return used;
}
