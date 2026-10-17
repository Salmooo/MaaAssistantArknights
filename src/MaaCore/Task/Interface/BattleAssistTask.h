#pragma once

#include "Task/InterfaceTask.h"

namespace asst
{
class BattleAssistTask final : public InterfaceTask
{
public:
    inline static constexpr std::string_view TaskType = "BattleAssist";

    BattleAssistTask(const AsstCallback& callback, Assistant* inst);
    virtual ~BattleAssistTask() override = default;
};
}
