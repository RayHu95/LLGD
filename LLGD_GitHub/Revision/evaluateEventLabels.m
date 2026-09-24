function [metrics, lineMetrics] = evaluateEventLabels(baselineLineLabels, predictedClusterLabels)
    baselineLineLabels = double(baselineLineLabels(:));
    predictedClusterLabels = double(predictedClusterLabels(:));
    if numel(baselineLineLabels) ~= numel(predictedClusterLabels)
        error('The two label vectors must have the same length.');
    end

    baselineLineLabels(~isfinite(baselineLineLabels) | baselineLineLabels <= 0) = 0;
    predictedClusterLabels(~isfinite(predictedClusterLabels) | predictedClusterLabels <= 0) = 0;
    lineIds = unique(baselineLineLabels(baselineLineLabels > 0));
    clusterIds = unique(predictedClusterLabels(predictedClusterLabels > 0));
    clusterSizes = zeros(numel(clusterIds), 1);
    for j = 1:numel(clusterIds)
        clusterSizes(j) = sum(predictedClusterLabels == clusterIds(j));
    end
    overlapMatrix = zeros(numel(lineIds), numel(clusterIds));

    lineMetrics = repmat(struct('lineLabel', 0, 'clusterLabel', 0, ...
        'coverage', 0, 'recall', 0, 'precision', 0, 'F1', 0, ...
        'IoU', 0, 'fragmentation', NaN), numel(lineIds), 1);
    for i = 1:numel(lineIds)
        lineMask = baselineLineLabels == lineIds(i);
        intersections = zeros(numel(clusterIds), 1);
        for j = 1:numel(clusterIds)
            intersections(j) = sum(lineMask & predictedClusterLabels == clusterIds(j));
        end
        overlapMatrix(i, :) = intersections;

        lineMetrics(i).lineLabel = lineIds(i);
        if ~isempty(intersections) && any(intersections > 0)
            [truePositive, bestIdx] = max(intersections);
            predictedNum = clusterSizes(bestIdx);
            coverage = truePositive / sum(lineMask);
            precision = truePositive / predictedNum;
            lineMetrics(i).clusterLabel = clusterIds(bestIdx);
            lineMetrics(i).coverage = coverage;
            lineMetrics(i).recall = coverage;
            lineMetrics(i).precision = precision;
            lineMetrics(i).F1 = 2 * coverage * precision / (coverage + precision);
            lineMetrics(i).IoU = truePositive / (sum(lineMask) + predictedNum - truePositive);
        end

        pureClusters = intersections ./ max(clusterSizes, 1) > 0.6;
        if any(pureClusters)
            lineMetrics(i).fragmentation = sum(pureClusters);
        end
    end

    baselineMask = baselineLineLabels > 0;
    predictedMask = predictedClusterLabels > 0;
    truePositive = sum(baselineMask & predictedMask);
    falseNegative = sum(baselineMask & ~predictedMask);
    falsePositive = sum(~baselineMask & predictedMask);
    metrics = struct('coverage', NaN, 'recall', NaN, 'precision', NaN, ...
        'F1', NaN, 'IoU', NaN, 'fragmentation', NaN, 'mergeError', NaN, ...
        'extraEventRatio', 0, 'lineCount', numel(lineIds), ...
        'clusterCount', numel(clusterIds));
    if truePositive + falseNegative > 0
        metrics.coverage = truePositive / (truePositive + falseNegative);
        metrics.recall = metrics.coverage;
    elseif truePositive + falsePositive > 0
        metrics.coverage = 0;
        metrics.recall = 0;
    end
    if truePositive + falsePositive > 0
        metrics.precision = truePositive / (truePositive + falsePositive);
        metrics.extraEventRatio = falsePositive / (truePositive + falsePositive);
    elseif truePositive + falseNegative > 0
        metrics.precision = 0;
    end
    if isfinite(metrics.coverage) && isfinite(metrics.precision) && ...
            metrics.coverage + metrics.precision > 0
        metrics.F1 = 2 * metrics.coverage * metrics.precision / ...
            (metrics.coverage + metrics.precision);
    elseif isfinite(metrics.coverage) && isfinite(metrics.precision)
        metrics.F1 = 0;
    end
    if truePositive + falsePositive + falseNegative > 0
        metrics.IoU = truePositive / ...
            (truePositive + falsePositive + falseNegative);
    end
    if truePositive > 0 && ~isempty(overlapMatrix)
        dominantSupport = sum(max(overlapMatrix, [], 1));
        metrics.mergeError = 1 - dominantSupport / truePositive;
    end
    if ~isempty(lineMetrics)
        fragmentation = [lineMetrics.fragmentation];
        if any(isfinite(fragmentation))
            metrics.fragmentation = mean(fragmentation(isfinite(fragmentation)));
        end
    end
end
