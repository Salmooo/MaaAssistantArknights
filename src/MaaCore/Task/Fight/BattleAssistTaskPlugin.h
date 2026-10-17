#pragma once

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

    virtual bool verify(AsstMsg msg, const json::value& details) const override;

protected:
    virtual bool _run() override;
    virtual AbstractTask& this_task() override { return *this; }

private:
    bool m_auto_use_skills = false;
    bool m_auto_speed_up = false;
};
}
