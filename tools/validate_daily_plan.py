"""核对每日策划的工时与交付字段，不判断游戏功能是否已完成。

读取单日JSON，逐岗位核算分钟与任务编号，避免在计划中叠加工时。
用法：python tools/validate_daily_plan.py <day_plan.json>
"""

import datetime
import json
import sys
from pathlib import Path

ROLES = ("程序", "主美术", "第二美术兼整合验收", "文案", "音效音乐")
TEXT_FIELDS = ("id", "owner", "work", "deliverable", "acceptance", "fallback")


def validate(plan):
    errors = []
    try:
        datetime.date.fromisoformat(plan.get("date", ""))
    except (TypeError, ValueError):
        errors.append("date必须是YYYY-MM-DD")
    if not isinstance(plan.get("day"), str) or not plan["day"].strip():
        errors.append("缺少day")
    tasks = plan.get("tasks")
    if not isinstance(tasks, list) or not tasks:
        return errors + ["tasks必须是非空数组"], {}
    totals = {role: 0 for role in ROLES}
    ids = set()
    for index, task in enumerate(tasks, 1):
        if not isinstance(task, dict):
            errors.append(f"任务{index}不是对象")
            continue
        for field in TEXT_FIELDS:
            if not isinstance(task.get(field), str) or not task[field].strip():
                errors.append(f"任务{index}缺少有效{field}")
        task_id = task.get("id")
        if isinstance(task_id, str):
            if task_id in ids:
                errors.append(f"重复任务编号{task_id}")
            ids.add(task_id)
        owner = task.get("owner")
        if owner not in ROLES:
            errors.append(f"任务{index}负责人不在5名制作成员中")
        minutes = task.get("minutes")
        if type(minutes) is not int or minutes <= 0:
            errors.append(f"任务{index}分钟必须是正整数")
        elif owner in totals:
            totals[owner] += minutes
        deps = task.get("depends_on")
        if not isinstance(deps, list) or any(not isinstance(d, str) for d in deps):
            errors.append(f"任务{index}缺少有效depends_on数组")
    for role, minutes in totals.items():
        if minutes == 0:
            errors.append(f"{role}没有当日任务")
        elif minutes > 120:
            errors.append(f"{role}合计{minutes}分钟，超过120")
    return errors, totals


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    try:
        plan = json.loads(Path(sys.argv[1]).read_text(encoding="utf-8-sig"))
        if not isinstance(plan, dict):
            raise ValueError("计划根节点必须是对象")
        errors, totals = validate(plan)
    except (OSError, ValueError) as error:
        print(f"计划读取失败：{error}")
        return 2
    for role, minutes in totals.items():
        print(f"{role}：{minutes}/120分钟")
    for error in errors:
        print(f"错误：{error}")
    print("计划校验通过" if not errors else "计划校验未通过")
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
