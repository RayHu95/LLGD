function plotRevisionAnalysis()
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    outputFolder = fullfile(codeRoot, 'Revision', 'results');
    files = {'revision_shapes_summary.csv', ...
        'revision_urban_summary.csv', 'revision_office_summary.csv'};
    names = {'shapes\_6dof', 'urban', 'office\_spiral'};
    parameters = {'MAD', 'p_in', 'p_w', 'overlap', 'eps_s', 'eps_t'};
    titles = {'MAD threshold', '$p_{in}$', '$p_w$', ...
        'Overlap threshold', '$\varepsilon_s$', '$\varepsilon_t$ (s)'};
    colors = [0.00, 0.45, 0.74; 0.85, 0.33, 0.10; 0.47, 0.67, 0.19];
    markers = {'o', 's', '^'};

    summary = cellfun(@(x) readtable(fullfile(outputFolder, x)), ...
        files, 'UniformOutput', false);
    figureHandle = figure('Color', 'w', 'Position', [80, 80, 1200, 650]);
    for parameterIdx = 1:numel(parameters)
        subplot(2, 3, parameterIdx);
        hold on;
        for datasetIdx = 1:numel(summary)
            rows = strcmp(summary{datasetIdx}.Category, 'Sensitivity') & ...
                strcmp(summary{datasetIdx}.Parameter, parameters{parameterIdx});
            values = summary{datasetIdx}.Value(rows);
            f1 = summary{datasetIdx}.F1(rows);
            [values, order] = sort(values);
            plot(values, f1(order), '-', 'Color', colors(datasetIdx, :), ...
                'Marker', markers{datasetIdx}, 'LineWidth', 1.2, ...
                'MarkerSize', 5, 'DisplayName', names{datasetIdx});
        end
        grid on;
        box on;
        xlabel(titles{parameterIdx}, 'Interpreter', 'latex');
        ylabel('$F_1$', 'Interpreter', 'latex');
        if parameterIdx == 1
            legend('Location', 'best', 'Interpreter', 'latex');
        end
    end
    set(findall(figureHandle, 'Type', 'axes'), 'FontName', ...
        'Times New Roman', 'FontSize', 9, 'LineWidth', 0.8);
    set(figureHandle, 'PaperPositionMode', 'auto');
    print(figureHandle, fullfile(outputFolder, 'parameter_sensitivity.png'), ...
        '-dpng', '-r300');
    print(figureHandle, fullfile(outputFolder, 'parameter_sensitivity.eps'), ...
        '-depsc2', '-painters');
end
