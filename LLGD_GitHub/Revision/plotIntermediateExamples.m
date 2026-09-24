function example = plotIntermediateExamples(packetIds, eventIds)
    if nargin < 1
        packetIds = [24,24,24];
        eventIds = [16,449,166];
    end
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(codeRoot, 'LineDetection'));
    addpath(fileparts(mfilename('fullpath')));
    sourceFile = fullfile(codeRoot, 'datasets', 'shapes_6dof_events.mat');
    loaded = load(sourceFile);
    data = loaded.data;
    eHeight = double(loaded.cam{1});
    eWidth = double(loaded.cam{2});
    timeOrigin = double(data(1).events(1,4)) + double(data(1).events(1,5))/1e9;
    parameters = struct('MADThreshold', 3.5, 'PinThreshold', 0.8, ...
        'PwThreshold', 0.8, 'OverlapThreshold', 0.8, ...
        'Eps1', 0.02, 'Eps2', 0.02, 'UseWeights', true, ...
        'UseVerification', true, 'UseGlobalExpansion', true);

    example.Dataset = 'shapes_6dof_events';
    example.Packet = packetIds(1);
    example.FrameIndex = loaded.frameIdx(example.Packet);
    example.Events = double(data(example.Packet).events);
    example.FrameTime = loaded.frameTime(example.Packet);
    example.TimeWindow = 0.02;
    example.GlobalSeed = 2025 + 100000 + example.Packet*1000 + 1;
    example.Parameters = parameters;
    config.detectorParameters = parameters;
    rng(example.GlobalSeed, 'twister');
    example.Labels = evaluateComparisonPacket('LLGD', example.Events, ...
        eWidth, eHeight, timeOrigin, config);

    for i = 1:3
        events = double(data(packetIds(i)).events);
        timestamp = events(:,4) + events(:,5)/1e9;
        points = [events(:,1)/eWidth, events(:,2)/eHeight];
        tree = KDTreeSearcher(points);
        neighbors = rangesearch(tree, points(eventIds(i),:), parameters.Eps1);
        neighbors = neighbors{1}';
        neighbors = neighbors(abs(timestamp(neighbors)-timestamp(eventIds(i))) <= parameters.Eps2);
        local.Packet = packetIds(i);
        local.FrameIndex = loaded.frameIdx(packetIds(i));
        local.EventId = eventIds(i);
        local.NeighborIds = neighbors;
        local.Events = events(neighbors,:);
        local.Center = events(eventIds(i),1:2);
        local.Seed = 2025 + 500000 + packetIds(i)*10000 + eventIds(i);
        options = parameters;
        options.UseVerification = false;
        rng(local.Seed, 'twister');
        [~, local.InitialModels, local.InitialInliers] = detectLineOnEI( ...
            points(neighbors,:), points(eventIds(i),:), eHeight, eWidth, false, options);
        options.UseVerification = true;
        rng(local.Seed, 'twister');
        [local.LineCount, local.Models, local.Inliers] = detectLineOnEI( ...
            points(neighbors,:), points(eventIds(i),:), eHeight, eWidth, false, options);
        [local.Pixels, ~, pixelIds] = unique(round(events(neighbors,1:2)), 'rows');
        local.Weights = accumarray(pixelIds, 1);
        local.InitialPixelIds = unique(pixelIds(local.InitialInliers>0));
        local.Pin = sum(local.InitialInliers>0)/numel(neighbors);
        heavy = local.Weights >= 3;
        local.Pw = sum(heavy(local.InitialPixelIds))/sum(heavy);
        local.PixelInliers = zeros(size(local.Pixels,1),1);
        for j = 1:local.LineCount
            local.PixelInliers(unique(pixelIds(local.Inliers==j))) = j;
        end
        example.Local(i) = local;
    end

    outputFolder = fullfile(codeRoot, 'Revision', 'results', 'intermediate');
    if ~isfolder(outputFolder), mkdir(outputFolder); end
    save(fullfile(outputFolder, 'intermediate_examples.mat'), 'example');
    index = table(packetIds(:), [example.Local.FrameIndex]', eventIds(:), ...
        [example.Local.Seed]', arrayfun(@(x) numel(x.NeighborIds), example.Local)', ...
        [example.Local.LineCount]', [example.Local.Pin]', [example.Local.Pw]', ...
        'VariableNames', {'Packet','FrameIndex','EventId','Seed','Events','Lines','Pin','Pw'});
    writetable(index, fullfile(outputFolder, 'intermediate_examples.csv'));
    drawExamples(example, eWidth, eHeight, outputFolder);
end

function drawExamples(example, eWidth, eHeight, outputFolder)
    figureHandle = figure('Color', 'w', 'Position', [80, 50, 1200, 900]);
    ax = axes('Position', [0.10, 0.59, 0.31, 0.31]);
    hold(ax, 'on');
    events = example.Events;
    time = events(:,4) + events(:,5)/1e9;
    time = (time-time(1))*1000;
    labels = example.Labels;
    scatter3(ax, time(labels<=0), events(labels<=0,1), events(labels<=0,2), ...
        3, [0.45,0.45,0.45], 'filled');
    ids = unique(labels(labels>0));
    colors = jet(numel(ids));
    for j = 1:numel(ids)
        keep = labels == ids(j);
        scatter3(ax, time(keep), events(keep,1), events(keep,2), ...
            6, colors(j,:), 'filled');
    end
    for j = 1:3
        local = example.Local(j);
        if local.Packet == example.Packet
            event = events(local.EventId,:);
            t = (event(4)+event(5)/1e9-events(1,4)-events(1,5)/1e9)*1000;
            plot3(ax, t, event(1), event(2), 'rx', 'MarkerSize', 9, 'LineWidth', 1.8);
            if j == 2
                text(ax, t, event(1)+13, event(2)+11, sprintf('e_%d',j), 'Color', 'r');
            else
                text(ax, t, event(1)+4, event(2), sprintf('e_%d',j), 'Color', 'r');
            end
        end
    end
    xlabel(ax, 'Time (ms)'); ylabel(ax, 'x'); zlabel(ax, 'y');
    ylim(ax, [0,eWidth]); zlim(ax, [0,eHeight]);
    set(ax, 'YDir', 'reverse', 'ZDir', 'reverse');
    view(ax, [-65,20]); grid(ax, 'on');
    title(ax, '(a) Expanded clusters');

    positions = [0.10,0.12,0.29,0.29; 0.495,0.59,0.18,0.31; ...
        0.725,0.59,0.18,0.31; 0.495,0.12,0.18,0.29; 0.725,0.12,0.18,0.29];
    locals = [1,2,2,3,3];
    final = [true,false,true,false,true];
    titles = {'(b) Single line', '(c) Initial fit', 'Two-line branch', ...
        '(d) Initial fit', 'Two-line branch'};
    for j = 1:5
        ax = axes('Position', positions(j,:));
        drawLocal(ax, example.Local(locals(j)), final(j), locals(j));
        title(ax, titles{j});
        if j==3 || j==5
            ylabel(ax, '');
            set(ax, 'YTickLabel', []);
        end
    end
    bar = colorbar(ax);
    bar.Position = [0.93,0.13,0.009,0.27];
    bar.Ticks = [0,0.5,1];
    set(findall(figureHandle, 'Type', 'axes'), 'FontName', 'Times New Roman', ...
        'FontSize', 20, 'LineWidth', 0.8);
    set(findall(figureHandle, 'Type', 'text'), 'FontName', 'Times New Roman', 'FontSize', 20);
    bar.FontSize = 18;
    set(figureHandle, 'PaperUnits', 'inches', 'PaperPosition', [0,0,12,9], ...
        'PaperSize', [12,9]);
    print(figureHandle, fullfile(outputFolder, 'intermediate_examples.png'), '-dpng', '-r300');
    print(figureHandle, fullfile(outputFolder, 'intermediate_examples.eps'), '-depsc2', '-painters');
    print(figureHandle, fullfile(outputFolder, 'intermediate_examples.pdf'), '-dpdf', '-painters');
    close(figureHandle);
end

function drawLocal(ax, local, final, number)
    pixels = local.Pixels;
    limits = [min(pixels(:,1))-1, max(pixels(:,1))+1, ...
        min(pixels(:,2))-1, max(pixels(:,2))+1];
    weightImage = zeros(limits(4)-limits(3)+1, limits(2)-limits(1)+1);
    offset = pixels - [limits(1),limits(3)] + 1;
    weightImage(sub2ind(size(weightImage),offset(:,2),offset(:,1))) = ...
        local.Weights/max(local.Weights);
    imagesc(ax, limits(1:2), limits(3:4), weightImage);
    colormap(ax, hot); caxis(ax, [0,1]);
    hold(ax, 'on'); axis(ax, 'image'); axis(ax, limits);
    xlabel(ax, 'x'); ylabel(ax, 'y');
    if final
        models = local.Models;
        colors = ['g','k'];
        for j = 1:local.LineCount
            keep = local.PixelInliers == j;
            scatter(ax, pixels(keep,1), pixels(keep,2), 16, colors(j), 'filled');
        end
    else
        models = local.InitialModels;
        keep = local.InitialPixelIds;
        scatter(ax, pixels(keep,1), pixels(keep,2), 16, 'g', 'filled');
        heavy = find(local.Weights>=3 & ~ismember((1:size(pixels,1))',keep));
        if ~isempty(heavy)
            [~, best] = max(local.Weights(heavy));
            p = pixels(heavy(best),:);
            plot(ax, p(1), p(2), 'gx', 'MarkerSize', 9, 'LineWidth', 1.6);
            text(ax, p(1)+0.4, p(2)-0.5, sprintf('x_{p%d}',number-1), 'Color', 'g');
        end
    end
    colors = ['r','w'];
    for j = 1:size(models,1)
        m = models(j,:);
        if abs(m(2)) >= abs(m(1))
            x = limits(1:2);
            y = -(m(1)*x+m(3))/m(2);
        else
            y = limits(3:4);
            x = -(m(2)*y+m(3))/m(1);
        end
        plot(ax, x, y, [colors(j),'-'], 'LineWidth', 1.6);
    end
    plot(ax, local.Center(1), local.Center(2), 'c+', 'MarkerSize', 8, 'LineWidth', 1.4);
    text(ax, limits(1)+0.5, limits(3)+0.6, sprintf('U(e_%d)',number), ...
        'Color', 'w', 'FontSize', 13);
end
