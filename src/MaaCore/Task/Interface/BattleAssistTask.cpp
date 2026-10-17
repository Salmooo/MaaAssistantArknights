#include "BattleAssistTask.h"

asst::BattleAssistTask::BattleAssistTask(const AsstCallback& callback, Assistant* inst) :
    InterfaceTask(callback, inst, TaskType)
{
}
