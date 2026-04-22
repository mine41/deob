Set-StrictMode -Version Latest

function Merge-UiTextPack {
    param([hashtable[]]$Packs)

    $merged = @{}
    foreach ($pack in @($Packs)) {
        if ($null -eq $pack) { continue }
        foreach ($key in @($pack.Keys)) {
            $merged[[string]$key] = $pack[$key]
        }
    }
    return $merged
}

function Get-UiText {
    param(
        [Parameter(Mandatory)][hashtable]$Pack,
        [Parameter(Mandatory)][string]$Key,
        [object[]]$Args = @()
    )

    if (-not $Pack.ContainsKey($Key)) {
        return $Key
    }

    $text = [string]$Pack[$Key]
    if ($null -eq $Args -or $Args.Count -eq 0) {
        return $text
    }

    return [string]::Format($text, $Args)
}

function Resolve-LocalizedDiagnosticMessage {
    param(
        [ValidateSet('zh-CN', 'en-US')][string]$Language = 'zh-CN',
        [string]$Reason,
        [string]$Message
    )

    if ($Language -ne 'en-US' -or [string]::IsNullOrWhiteSpace([string]$Message)) {
        return $Message
    }

    $text = [string]$Message
    $exactMap = @{
        'ExpandableString 内仅放行高价值高置信候选，当前候选跳过' = 'Within ExpandableString, only high-value, high-confidence candidates are allowed; current candidate skipped'
        '与已选片段重叠（Inner 策略丢弃外层/冲突）' = 'Overlaps with an already selected fragment (Inner strategy dropped the outer/conflicting candidate)'
        '进入静态候选阶段时全局预算已耗尽，跳过静态求值。' = 'Global budget was already exhausted before static candidate evaluation; skipped static evaluation.'
        '替换后语法错误，移除该候选以保持脚本可解析' = 'Replacement caused a syntax error; removed this candidate to keep the script parseable'
        '变量读取值非简单字面量，跳过替换' = 'Variable read value is not a simple literal; skipped replacement'
        'CommandAst 不是 EncodedCommand 调用' = 'CommandAst is not an EncodedCommand call'
        '括号表达式不是简单表达式' = 'Parenthesized expression is not a simple expression'
        '不支持有副作用的一元操作' = 'Unary operations with side effects are not supported'
        'AST 为空' = 'AST is empty'
        '未知二元操作符' = 'Unknown binary operator'
        '未知一元操作符' = 'Unknown unary operator'
        '未知转换类型' = 'Unknown conversion type'
        '变量 AST 无效' = 'Variable AST is invalid'
        '子表达式包含 trap 或为空' = 'Subexpression contains trap or is empty'
        '子表达式包含非 Pipeline 语句' = 'Subexpression contains a non-pipeline statement'
        '子表达式包含复杂 pipeline' = 'Subexpression contains a complex pipeline'
        '数组表达式包含 trap 或为空' = 'Array expression contains trap or is empty'
        '数组表达式包含非 Pipeline 语句' = 'Array expression contains a non-pipeline statement'
        '数组表达式包含复杂 pipeline' = 'Array expression contains a complex pipeline'
        '动态参数依赖被阻断命令，保留已解析命令文本但不执行。' = 'Dynamic argument depends on a blocked command; preserved the resolved command text without executing it.'
        '动态脚本文本解析失败，停止递归执行，直接回写当前解出的脚本内容。' = 'Dynamic script text could not be parsed; stopped recursive execution and preserved the current resolved script text.'
        '检测到顶层无限循环特征，停止递归执行动态脚本，直接回写当前解出的脚本内容。' = 'Detected a top-level infinite loop pattern; stopped recursive execution of the dynamic script and preserved the current resolved script text.'
        '检测到网络获取与动态执行组合，停止递归执行动态脚本，直接回写当前解出的脚本内容。' = 'Detected a combination of network retrieval and dynamic execution; stopped recursive execution of the dynamic script and preserved the current resolved script text.'
        '检测到网络轮询与休眠组合，停止递归执行动态脚本，直接回写当前解出的脚本内容。' = 'Detected a combination of network polling and sleep; stopped recursive execution of the dynamic script and preserved the current resolved script text.'
        '检测到 shellcode 注入特征，停止递归执行动态脚本，直接回写当前解出的脚本内容。' = 'Detected shellcode injection characteristics; stopped recursive execution of the dynamic script and preserved the current resolved script text.'
        '检测到 COM GUI/自动化特征，停止递归执行动态脚本，直接回写当前解出的脚本内容。' = 'Detected COM GUI/automation characteristics; stopped recursive execution of the dynamic script and preserved the current resolved script text.'
        '静态求值失败' = 'Static evaluation failed'
    }
    if ($exactMap.ContainsKey($text)) {
        return [string]$exactMap[$text]
    }

    switch -Regex ($text) {
        '^同一片段出现多个值:\s*(\d+)$' {
            return "Multiple values found for the same fragment: $($Matches[1])"
        }
        '^静态结果非标量:\s*(.+)$' {
            return "Static result is non-scalar: $($Matches[1])"
        }
        '^变量不存在:\s*(.+)$' {
            return "Variable does not exist: $($Matches[1])"
        }
        '^变量值类型不支持静态求值:\s*(.+)$' {
            return "Variable value type is not supported for static evaluation: $($Matches[1])"
        }
        '^不支持的 AST 类型:\s*(.+)$' {
            return "Unsupported AST type: $($Matches[1])"
        }
        '^变量读取同位置多值\((\d+)\)，策略=skip，跳过$' {
            return "Variable read has multiple values at the same location ($($Matches[1])); policy=skip, skipped"
        }
        '^替换后语法错误，移除 (.+) 候选$' {
            return "Replacement caused a syntax error; removed the $($Matches[1]) candidate"
        }
        '^单次动态展开预算已耗尽（Elapsed=(\d+)ms, Budget=(\d+)ms），停止继续深入，直接回写当前脚本内容。$' {
            return "Dynamic expansion budget exhausted for this invocation (Elapsed=$($Matches[1])ms, Budget=$($Matches[2])ms); stopped recursion and preserved the current script text."
        }
        '^同片段多值:\s*(\d+)$' {
            return "Multiple values found for the same fragment: $($Matches[1])"
        }
        '^变量同位置多值且无可用最终值:\s*(\d+)$' {
            return "Variable has multiple values at the same location and no final value is available: $($Matches[1])"
        }
    }

    switch ($Reason) {
        'dynamic_node_missing' { return $text -replace '^DynamicInvoke 节点不存在:', 'DynamicInvoke node not found:' }
        'dynamic_runtime_node' { return 'DynamicInvoke inside a runtime subgraph is not written back to the original script directly' }
        'dynamic_no_offset' { return 'DynamicInvoke has no original offset; skipped' }
        'dynamic_out_of_range' { return 'DynamicInvoke offset is out of range' }
        'dynamic_empty' { return 'DynamicInvoke resolved to empty content; skipped' }
        'no_change' {
            if ($text -eq '无变化') { return 'No change' }
            if ($text -eq '变量 replacement 无变化') { return 'Variable replacement produced no change' }
            if ($text -eq 'DynamicInvoke replacement 与原片段一致') { return 'DynamicInvoke replacement matches the original fragment' }
        }
        'merge_same_range' { return 'Candidates conflict on the same range; kept the higher-priority candidate' }
        'prefer_dynamic_invoke' { return 'Inner candidate is covered by a higher-priority DynamicInvoke candidate; kept the full dynamic code replacement' }
        'static_no_offset' { return 'Static candidate has no offset' }
        'static_out_of_range' { return 'Static candidate offset is out of range' }
        'static_no_ast' { return 'Static candidate has no AST' }
        'static_blocked' { return 'Static result is a placeholder; skipped' }
        'static_no_change' { return 'Static replacement produced no change' }
        'runtime_generated' {
            if ($text -eq '运行时子图的 Resolvable 不直接回写原脚本') { return 'Resolvable inside a runtime subgraph is not written back to the original script directly' }
            if ($text -eq '运行时子图的变量读取不直接回写原脚本') { return 'Variable reads inside a runtime subgraph are not written back to the original script directly' }
        }
        'no_offset' { return 'No offset' }
        'out_of_range' { return 'Offset is out of range' }
        'blocked' {
            if ($text -eq '占位符跳过') { return 'Placeholder skipped' }
            if ($text -eq '变量值为占位符跳过') { return 'Variable value is a placeholder; skipped' }
        }
        'null_replacement' {
            if ($text -eq 'replacement 为 $null，默认跳过') { return 'Replacement is $null; skipped by default' }
            if ($text -eq '变量 replacement 为 $null，默认跳过') { return 'Variable replacement is $null; skipped by default' }
        }
        'conflict_same_range' {
            if ($text -eq '同区间冲突') { return 'Conflict on the same range' }
            if ($text -eq '变量同区间冲突') { return 'Variable conflict on the same range' }
        }
        'var_write_context' { return $text -replace '^变量位点为 ', 'Variable access is in ' -replace ' 上下文，跳过替换（避免生成无效语法）$', ' context; skipped replacement to avoid generating invalid syntax' }
        'overlap' {
            if ($text -eq 'Outer 丢弃重叠') { return 'Outer strategy dropped an overlapping candidate' }
            if ($text -eq 'Inner 丢弃重叠') { return 'Inner strategy dropped an overlapping candidate' }
        }
        'overlap_conflict' {
            if ($text -eq '手动选择冲突，保留优先级更高片段') { return 'Manual selection conflict; kept the higher-priority fragment' }
            if ($text -eq '自动选择冲突，保留优先级更高片段') { return 'Automatic selection conflict; kept the higher-priority fragment' }
        }
        'syntax_guard_fallback' { return 'Replacements still caused a syntax error; cleared all replacements' }
    }

    return $text
}

function Convert-UiTextKeyToToken {
    param([Parameter(Mandatory)][string]$Key)

    $name = $Key.ToUpperInvariant()
    $name = [System.Text.RegularExpressions.Regex]::Replace($name, '[^A-Z0-9]+', '_')
    return "__LOC_${name}__"
}

function Resolve-LocalizedTemplate {
    param(
        [Parameter(Mandatory)][string]$Template,
        [Parameter(Mandatory)][hashtable]$Pack
    )

    $resolved = $Template
    foreach ($key in @($Pack.Keys | Sort-Object { [string]$_ })) {
        if (-not ([string]$key).StartsWith('xaml.')) { continue }
        $token = Convert-UiTextKeyToToken -Key ([string]$key)
        $value = [System.Security.SecurityElement]::Escape([string]$Pack[$key])
        $resolved = $resolved.Replace($token, $value)
    }

    return $resolved
}

function Get-ReplayUiTextPack {
    param([ValidateSet('zh-CN', 'en-US')][string]$Language)

    switch ($Language) {
        'en-US' {
            return @{
                'folder.description'                  = 'Select a *.work folder (for example: xxx.rebuilt.ps1.work)'
                'message.no_round_found'              = 'No round*.execution.log was found in:{0}{1}'
                'title.no_round_found'                = 'Round Not Found'
                'title.round_picker'                  = 'Select Round'
                'xaml.round_picker.window_title'      = 'Select Round'
                'xaml.round_picker.prompt'            = 'Choose the round to replay:'
                'xaml.round_picker.round_header'      = 'Round'
                'xaml.round_picker.report_header'     = 'Report'
                'xaml.round_picker.btn_ok'            = 'OK'
                'xaml.round_picker.btn_cancel'        = 'Cancel'
                'report.none_short'                   = '(no report)'
                'round.report_summary'                = 'candidates={0} applied={1} skipped={2}{3}'
                'round.report_host_suffix'            = ' host={0}'
                'message.invalid_workdir'             = 'Invalid WorkDir'
                'message.no_frames'                   = '(no available frames)'
                'xaml.window_title'                   = 'CFG Execution Replay'
                'xaml.btn_open_workdir'               = 'Open Folder'
                'xaml.btn_change_round'               = 'Change Round'
                'xaml.btn_prev'                       = 'Prev'
                'xaml.btn_next'                       = 'Next'
                'xaml.btn_reset'                      = 'Reset'
                'xaml.btn_last'                       = 'Run To End'
                'xaml.zoom_label'                     = 'CFG Zoom'
                'xaml.tab_current_node'               = 'Current Node'
                'xaml.group_current_recovery'         = 'Current Node Recovery'
                'xaml.column_status'                  = 'Status'
                'xaml.group_original_full'            = 'Full Original'
                'xaml.group_replacement_full'         = 'Full Replacement/Message'
                'xaml.tab_variables'                  = 'Variables'
                'xaml.group_variable_state'           = 'Variable State'
                'xaml.column_variable'                = 'Variable'
                'xaml.column_value'                   = 'Value'
                'xaml.group_vars_read'                = 'Node VarsRead'
                'xaml.group_vars_written'             = 'Node VarsWritten'
                'xaml.group_scope_stack'              = 'Scope Stack'
                'xaml.tab_report'                     = 'Report'
                'xaml.tab_applied'                    = 'Applied'
                'xaml.tab_skipped'                    = 'Skipped'
                'report.summary'                      = 'candidates={0} applied={1} skipped={2}  (strategy={3}){4}'
                'report.summary_host_suffix'          = '  host={0}'
                'report.none'                         = '(no report.json)'
                'recovery.status.applied'             = 'Applied'
                'recovery.status.skipped'             = 'Skipped'
                'graph.placeholder.missing_png'       = '(round{0}.cfg.png not found)'
                'graph.placeholder.load_png_failed'   = '(failed to load cfg.png: {0})'
                'graph.placeholder.no_layout'         = '(cfg.dot not found or dot -Tplain unavailable; graph is not interactive)'
                'tooltip.visits'                      = 'Visits'
                'status.empty'                        = 'WorkDir={0} | Round={1} | (no available frames)'
                'status.main'                         = 'WorkDir={0} | Round={1} | Frame={2}/{3} | Node={4} [{5}] | Status={6}'
                'node.header'                         = 'Node {0} [{1}]'
                'node.meta'                           = 'Time={0}  Status={1}  Action={2}  Target={3}  Reason={4}  Result={5}  Condition={6}'
                'scope.item'                          = '{0} {1} (prefix={2})'
                'menu.copy_original'                  = 'Copy Original'
                'menu.copy_replacement'               = 'Copy Replacement/Message'
                'message.open_failed_title'           = 'Open Failed'
                'message.open_failed_load'            = 'Load failed: {0}'
                'message.change_round_failed'         = 'Failed to switch round: {0}'
                'message.change_round_failed_title'   = 'Change Round Failed'
                'window.title.with_host'              = 'CFG Execution Replay - Round {0} [{1}]'
                'window.title.no_host'                = 'CFG Execution Replay - Round {0}'
            }
        }
        default {
            return @{
                'folder.description'                  = '选择 *.work 工作目录（例如: xxx.rebuilt.ps1.work）'
                'message.no_round_found'              = '目录中未找到 round*.execution.log:{0}{1}'
                'title.no_round_found'                = '未找到 Round'
                'title.round_picker'                  = '选择 Round'
                'xaml.round_picker.window_title'      = '选择 Round'
                'xaml.round_picker.prompt'            = '请选择要复盘的 round：'
                'xaml.round_picker.round_header'      = 'Round'
                'xaml.round_picker.report_header'     = 'Report'
                'xaml.round_picker.btn_ok'            = 'OK'
                'xaml.round_picker.btn_cancel'        = 'Cancel'
                'report.none_short'                   = '(无 report)'
                'round.report_summary'                = '候选={0} 已应用={1} 已跳过={2}{3}'
                'round.report_host_suffix'            = ' 宿主={0}'
                'message.invalid_workdir'             = '无效 WorkDir'
                'message.no_frames'                   = '(无可用帧)'
                'xaml.window_title'                   = 'CFG 执行复盘器'
                'xaml.btn_open_workdir'               = '打开文件'
                'xaml.btn_change_round'               = '更换 Round'
                'xaml.btn_prev'                       = '上一步'
                'xaml.btn_next'                       = '下一步'
                'xaml.btn_reset'                      = '重置'
                'xaml.btn_last'                       = '执行到最后'
                'xaml.zoom_label'                     = 'CFG缩放'
                'xaml.tab_current_node'               = '当前节点'
                'xaml.group_current_recovery'         = '当前节点还原片段'
                'xaml.column_status'                  = '状态'
                'xaml.group_original_full'            = 'Original 全文'
                'xaml.group_replacement_full'         = 'Replacement/Message 全文'
                'xaml.tab_variables'                  = '变量'
                'xaml.group_variable_state'           = '累计变量状态'
                'xaml.column_variable'                = '变量'
                'xaml.column_value'                   = '值'
                'xaml.group_vars_read'                = '本节点 VarsRead'
                'xaml.group_vars_written'             = '本节点 VarsWritten'
                'xaml.group_scope_stack'              = 'ScopeStack'
                'xaml.tab_report'                     = 'Report'
                'xaml.tab_applied'                    = 'Applied'
                'xaml.tab_skipped'                    = 'Skipped'
                'report.summary'                      = '候选={0} 已应用={1} 已跳过={2}  (策略={3}){4}'
                'report.summary_host_suffix'          = '  宿主={0}'
                'report.none'                         = '(无 report.json)'
                'recovery.status.applied'             = '已应用'
                'recovery.status.skipped'             = '已跳过'
                'graph.placeholder.missing_png'       = '(未找到 round{0}.cfg.png)'
                'graph.placeholder.load_png_failed'   = '(加载 cfg.png 失败: {0})'
                'graph.placeholder.no_layout'         = '(未找到 cfg.dot 或无法运行 dot -Tplain，节点图不可交互)'
                'tooltip.visits'                      = '访问次数'
                'status.empty'                        = 'WorkDir={0} | Round={1} | (无可用帧)'
                'status.main'                         = 'WorkDir={0} | Round={1} | Frame={2}/{3} | Node={4} [{5}] | Status={6}'
                'node.header'                         = 'Node {0} [{1}]'
                'node.meta'                           = 'Time={0}  Status={1}  Action={2}  Target={3}  Reason={4}  Result={5}  Condition={6}'
                'scope.item'                          = '{0} {1} (prefix={2})'
                'menu.copy_original'                  = '复制 Original'
                'menu.copy_replacement'               = '复制 Replacement/Message'
                'message.open_failed_title'           = '打开文件失败'
                'message.open_failed_load'            = '加载失败: {0}'
                'message.change_round_failed'         = '切换 round 失败: {0}'
                'message.change_round_failed_title'   = '更换 Round 失败'
                'window.title.with_host'              = 'CFG 执行复盘器 - Round {0} [{1}]'
                'window.title.no_host'                = 'CFG 执行复盘器 - Round {0}'
            }
        }
    }
}

function Get-DebugUiTextPack {
    param([ValidateSet('zh-CN', 'en-US')][string]$Language)

    switch ($Language) {
        'en-US' {
            return @{
                'xaml.window_title'                      = 'Deobfuscation Debugger'
                'xaml.btn_next'                          = 'Next'
                'xaml.btn_run_all'                       = 'Run To End'
                'xaml.btn_reset'                         = 'Reset'
                'xaml.btn_export'                        = 'Export Rebuilt Script'
                'xaml.zoom_label'                        = 'CFG Zoom'
                'xaml.column_scope'                      = 'Scope'
                'xaml.tab_current_node'                  = 'Current Node'
                'xaml.column_replace'                    = 'Apply'
                'xaml.column_source'                     = 'Source'
                'xaml.column_confidence'                 = 'Confidence'
                'xaml.column_variable'                   = 'Variable'
                'xaml.column_changed'                    = 'Changed'
                'xaml.tab_variable_stack'                = 'Variable Stack'
                'xaml.column_display_name'               = 'Variable'
                'xaml.column_actual_name'                = 'Actual Name'
                'xaml.column_value'                      = 'Value'
                'xaml.current_variable'                  = 'Current variable:'
                'xaml.new_value_expression'              = 'New value expression:'
                'xaml.btn_apply_var'                     = 'Apply Variable'
                'xaml.btn_refresh_var'                   = 'Refresh'
                'xaml.chk_advanced'                      = 'Advanced internal vars'
                'xaml.tab_export_preview'                = 'Export Preview'
                'xaml.tab_runtime_subgraphs'             = 'Runtime Subgraphs'
                'export.success_message'                 = 'Export completed:{0}{1}{0}{2}'
                'export.success_title'                   = 'Export Completed'
                'error.title'                            = 'PSDissect Debug Error'
                'error.ui_message'                       = 'Action failed: {0}{1}{0}{2}{0}{0}Detailed stack trace was written to:{0}{3}'
                'error.action_ui'                        = 'UI'
                'var.prompt_select'                      = 'Select a variable, or enter a variable name directly.'
                'var.prompt_expression'                  = 'Enter a new value expression for the variable.'
                'var.prompt_title'                       = 'Notice'
                'var.error_set_failed'                   = 'Failed to set variable: {0}'
                'var.error_title'                        = 'Error'
                'status.base'                            = 'Script={0} | Steps={1} | Visits={2} | Runtime={3} | Completed={4}'
                'status.hold'                            = '{0} | Hold={1}->{2}'
                'preview.summary'                        = 'candidates={0} | selected={1} | skipped={2} | static.high={3} | static.low={4} | changed.vars={5} | strategy={6} | manual.rules={7}'
                'preview.low_conf_note'                  = '{0} | low-confidence static candidates are unchecked by default'
                'preview.auto_uncheck_named'             = 'Variable values changed; unchecked: {0}'
                'preview.auto_uncheck_generic'           = 'Variable values changed; related selections were unchecked automatically.'
                'dynamic.none_summary'                   = 'Runtime subgraphs: 0'
                'dynamic.none_detail'                    = 'No runtime subgraphs have been triggered yet.'
                'dynamic.summary'                        = 'Runtime subgraphs: {0} | active: {1} | host: {2}'
                'dynamic.field.block'                    = 'BlockName'
                'dynamic.field.type'                     = 'Type'
                'dynamic.field.status'                   = 'Status'
                'dynamic.field.parent'                   = 'Parent'
                'dynamic.field.caller'                   = 'Caller'
                'dynamic.field.caller_text'              = 'CallerText'
                'dynamic.field.arg_code'                 = 'ArgCode'
                'dynamic.field.code'                     = 'Code'
                'dynamic.field.stop_reason'              = 'StopReason'
                'dynamic.field.stop_message'             = 'StopMsg'
                'dynamic.field.range'                    = 'Range'
                'dynamic.field.current'                  = 'Current'
                'dynamic.status.current'                 = 'Current'
                'dynamic.status.open'                    = 'Open'
                'dynamic.status.returned'                = 'Returned'
                'replace.none'                           = 'Current node replacement candidates: 0'
                'replace.source_static'                  = 'Static'
                'replace.source_dynamic'                 = 'Dynamic'
                'replace.confidence.high'                = 'High'
                'replace.confidence.low'                 = 'Low'
                'replace.changed_flag'                   = 'Yes'
                'replace.summary'                        = 'Current node replacement candidates: {0} | selected: {1} | static.high: {2} | static.low: {3}'
                'replace.summary_source_node'            = '{0} | showing source node {1} candidates'
                'replace.summary_changed'                = '{0} | changed vars: {1}'
                'replace.summary_low_conf'               = '{0} | low-confidence static candidates are unchecked by default'
                'replace.summary_note'                   = '{0} | note: changed variables are unchecked by default; re-check to export the latest value'
                'replace.selection_updated'              = 'Replacement selection updated'
                'step.scope.runtime'                     = 'Runtime'
                'step.scope.static'                      = 'Static'
                'step.next_plain'                        = '-> {0}'
                'step.next_labeled'                      = '{0} -> {1}'
                'node.completed'                         = '(execution completed)'
                'node.stop_reason'                       = 'StopReason={0}'
                'node.next.none'                         = 'Next edge: (none)'
                'node.header.runtime'                    = 'Node {0} [{1}] | Runtime {2}'
                'node.header.static'                     = 'Node {0} [{1}]'
                'node.meta.hold'                         = 'This node has executed and produced replacement candidates. Select the replacements, then click Next again to enter the successor node.'
                'node.meta.pending'                      = 'This node has not executed yet. Click Next to execute it.'
                'node.meta.runtime.base'                 = ' You are currently inside runtime subgraph {0}'
                'node.meta.runtime.caller'               = '{0}, originating from caller node {1}.'
                'node.meta.runtime.no_caller'            = '{0}.'
                'node.meta.runtime.code'                 = '{0} Dynamic code: {1}'
                'node.meta.runtime_stop'                 = ' Dynamic recursion stopped: {0}.'
                'node.meta.runtime_stop_message'         = '{0} {1}'
                'node.next.advance_plain'                = 'Next step will advance to: Node {0}'
                'node.next.advance_labeled'              = 'Next step will advance: {0} -> Node {1}'
                'node.next.predict_error'                = 'Predicted next edge: (unavailable) {0}'
                'node.next.predict_with_condition'       = 'Predicted next edge: {0} -> Node {1} (Condition={2})'
                'node.next.predict'                      = 'Predicted next edge: {0} -> Node {1}'
                'node.next.predict_none'                 = 'Predicted next edge: (none)'
                'status.graph_refreshed'                 = 'CFG graph refreshed to include the current runtime subgraphs'
                'reset.cfg_failed'                       = 'Reset failed: could not rebuild CFG: {0}'
                'btn_next_hold'                          = 'Node executed; waiting for replacement selection before advancing'
                'var.changed_selected'                   = 'Selected changed variable {0}; export will use the latest value'
                'var.set_status'                         = 'Set {0} = {1}'
                'graph.placeholder.missing_png'          = '(cfg.png not found)'
                'graph.placeholder.load_png_failed'      = '(failed to load cfg.png: {0})'
                'graph.refresh_failed'                   = 'Failed to refresh CFG graph ({0}): {1}'
            }
        }
        default {
            return @{
                'xaml.window_title'                      = '解混淆调试模式'
                'xaml.btn_next'                          = '下一步'
                'xaml.btn_run_all'                       = '执行到最后'
                'xaml.btn_reset'                         = '重置'
                'xaml.btn_export'                        = '导出重建脚本'
                'xaml.zoom_label'                        = 'CFG缩放'
                'xaml.column_scope'                      = '域'
                'xaml.tab_current_node'                  = '当前节点'
                'xaml.column_replace'                    = '替换'
                'xaml.column_source'                     = '来源'
                'xaml.column_confidence'                 = '置信'
                'xaml.column_variable'                   = '变量'
                'xaml.column_changed'                    = '变化'
                'xaml.tab_variable_stack'                = '变量栈'
                'xaml.column_display_name'               = '变量'
                'xaml.column_actual_name'                = '实际名'
                'xaml.column_value'                      = '值'
                'xaml.current_variable'                  = '当前变量:'
                'xaml.new_value_expression'              = '新值表达式:'
                'xaml.btn_apply_var'                     = '应用变量'
                'xaml.btn_refresh_var'                   = '刷新'
                'xaml.chk_advanced'                      = '高级内部变量'
                'xaml.tab_export_preview'                = '导出预览'
                'xaml.tab_runtime_subgraphs'             = '动态子图'
                'export.success_message'                 = '导出完成：{0}{1}{0}{2}'
                'export.success_title'                   = '导出完成'
                'error.title'                            = 'PSDissect 调试错误'
                'error.ui_message'                       = '操作失败: {0}{1}{0}{2}{0}{0}详细堆栈已写入:{0}{3}'
                'error.action_ui'                        = 'UI'
                'var.prompt_select'                      = '请选择变量，或直接输入变量名。'
                'var.prompt_expression'                  = '请输入变量新值表达式。'
                'var.prompt_title'                       = '提示'
                'var.error_set_failed'                   = '设置变量失败: {0}'
                'var.error_title'                        = '错误'
                'status.base'                            = 'Script={0} | Steps={1} | Visits={2} | Runtime={3} | Completed={4}'
                'status.hold'                            = '{0} | Hold={1}->{2}'
                'preview.summary'                        = '候选片段={0} | 当前选择={1} | 跳过={2} | 静态高={3} | 静态低={4} | 变化变量={5} | 默认策略={6} | 手动规则={7}'
                'preview.low_conf_note'                  = '{0} | 低置信静态候选默认不勾选'
                'preview.auto_uncheck_named'             = '检测到变量值变化，已取消勾选: {0}'
                'preview.auto_uncheck_generic'           = '检测到变量值变化，已自动取消相关勾选。'
                'dynamic.none_summary'                   = '运行时动态子图: 0'
                'dynamic.none_detail'                    = '当前尚未触发运行时动态子图。'
                'dynamic.summary'                        = '运行时动态子图: {0} | 活动中: {1} | 当前宿主: {2}'
                'dynamic.field.block'                    = 'BlockName'
                'dynamic.field.type'                     = 'Type'
                'dynamic.field.status'                   = 'Status'
                'dynamic.field.parent'                   = 'Parent'
                'dynamic.field.caller'                   = 'Caller'
                'dynamic.field.caller_text'              = 'CallerText'
                'dynamic.field.arg_code'                 = 'ArgCode'
                'dynamic.field.code'                     = 'Code'
                'dynamic.field.stop_reason'              = 'StopReason'
                'dynamic.field.stop_message'             = 'StopMsg'
                'dynamic.field.range'                    = 'Range'
                'dynamic.field.current'                  = 'Current'
                'dynamic.status.current'                 = 'Current'
                'dynamic.status.open'                    = 'Open'
                'dynamic.status.returned'                = 'Returned'
                'replace.none'                           = '当前节点可替换片段: 0'
                'replace.source_static'                  = '静态'
                'replace.source_dynamic'                 = '动态'
                'replace.confidence.high'                = '高'
                'replace.confidence.low'                 = '低'
                'replace.changed_flag'                   = '是'
                'replace.summary'                        = '当前节点可替换片段: {0} | 已选择: {1} | 静态高: {2} | 静态低: {3}'
                'replace.summary_source_node'            = '{0} | 显示来源节点 Node {1} 的候选'
                'replace.summary_changed'                = '{0} | 值变化变量: {1}'
                'replace.summary_low_conf'               = '{0} | 低置信静态候选默认不勾选'
                'replace.summary_note'                   = '{0} | 说明：值变化变量默认取消勾选，手动再勾选将使用最后值'
                'replace.selection_updated'              = '片段选择已更新'
                'step.scope.runtime'                     = 'Runtime'
                'step.scope.static'                      = 'Static'
                'step.next_plain'                        = '-> {0}'
                'step.next_labeled'                      = '{0} -> {1}'
                'node.completed'                         = '(执行结束)'
                'node.stop_reason'                       = 'StopReason={0}'
                'node.next.none'                         = '下一边: (无)'
                'node.header.runtime'                    = 'Node {0} [{1}] | Runtime {2}'
                'node.header.static'                     = 'Node {0} [{1}]'
                'node.meta.hold'                         = '该节点已执行并产生可替换片段。请勾选替换项，再次点击 ''下一步'' 进入后继节点。'
                'node.meta.pending'                      = '当前尚未执行该节点。点击 ''下一步'' 执行。'
                'node.meta.runtime.base'                 = ' 当前位于运行时子图 {0}'
                'node.meta.runtime.caller'               = '{0}，来源调用节点为 Node {1}。'
                'node.meta.runtime.no_caller'            = '{0}。'
                'node.meta.runtime.code'                 = '{0} 动态代码: {1}'
                'node.meta.runtime_stop'                 = ' 动态递归已停止: {0}。'
                'node.meta.runtime_stop_message'         = '{0} {1}'
                'node.next.advance_plain'                = '下一步将前进到: Node {0}'
                'node.next.advance_labeled'              = '下一步将前进: {0} -> Node {1}'
                'node.next.predict_error'                = '预计下一边: (无法预估) {0}'
                'node.next.predict_with_condition'       = '预计下一边: {0} -> Node {1} (Condition={2})'
                'node.next.predict'                      = '预计下一边: {0} -> Node {1}'
                'node.next.predict_none'                 = '预计下一边: (无)'
                'status.graph_refreshed'                 = 'CFG 图已按当前运行时子图刷新'
                'reset.cfg_failed'                       = '重置失败：无法重新生成 CFG: {0}'
                'btn_next_hold'                          = '节点已执行，等待选择替换片段后再前进'
                'var.changed_selected'                   = '已勾选变化变量 {0}，导出时将使用最后值'
                'var.set_status'                         = 'Set {0} = {1}'
                'graph.placeholder.missing_png'          = '(未找到 cfg.png)'
                'graph.placeholder.load_png_failed'      = '(加载 cfg.png 失败: {0})'
                'graph.refresh_failed'                   = '动态刷新 CFG 图失败({0}): {1}'
            }
        }
    }
}

function Get-UiTextPack {
    param(
        [Parameter(Mandatory)][ValidateSet('Replay', 'Debug')][string]$Scope,
        [ValidateSet('zh-CN', 'en-US')][string]$Language = 'zh-CN'
    )

    switch ($Scope) {
        'Replay' { return Get-ReplayUiTextPack -Language $Language }
        'Debug'  { return Get-DebugUiTextPack -Language $Language }
    }
}

function Show-LanguageSelectionDialog {
    [xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="选择语言 / Select Language" Height="190" Width="420"
        WindowStartupLocation="CenterScreen" ResizeMode="NoResize"
        WindowStyle="SingleBorderWindow">
  <Grid Margin="16">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="请选择界面语言 / Select UI language" FontSize="16" FontWeight="Bold" TextWrapping="Wrap"/>
    <TextBlock Grid.Row="1" Margin="0,8,0,0" Foreground="#555" Text="仅对本次运行生效 / This applies to the current session only." TextWrapping="Wrap"/>
    <StackPanel Grid.Row="2" Orientation="Horizontal" HorizontalAlignment="Center" VerticalAlignment="Center" Margin="0,20,0,12">
      <Button Name="BtnChinese" Content="中文" Width="120" Height="38" Margin="0,0,12,0"/>
      <Button Name="BtnEnglish" Content="English" Width="120" Height="38"/>
    </StackPanel>
    <StackPanel Grid.Row="3" Orientation="Horizontal" HorizontalAlignment="Right">
      <Button Name="BtnCancel" Content="Cancel" Width="90" IsCancel="True"/>
    </StackPanel>
  </Grid>
</Window>
'@

    $reader = New-Object System.Xml.XmlNodeReader $xaml
    $window = [System.Windows.Markup.XamlReader]::Load($reader)
    $btnChinese = $window.FindName('BtnChinese')
    $btnEnglish = $window.FindName('BtnEnglish')

    $btnChinese.Add_Click({
        $window.Tag = 'zh-CN'
        $window.DialogResult = $true
        $window.Close()
    })
    $btnEnglish.Add_Click({
        $window.Tag = 'en-US'
        $window.DialogResult = $true
        $window.Close()
    })
    $window.Add_ContentRendered({
        $null = $btnChinese.Focus()
    })

    $null = $window.ShowDialog()
    if ($null -ne $window.Tag) {
        return [string]$window.Tag
    }
    return $null
}
