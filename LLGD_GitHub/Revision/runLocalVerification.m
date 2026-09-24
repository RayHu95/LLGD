function [detail, samples] = runLocalVerification()
    codeRoot = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(codeRoot, 'LineDetection'));
    outputFolder = fullfile(codeRoot, 'Revision', 'results', 'component_split');
    if ~isfolder(outputFolder), mkdir(outputFolder); end
    rng(2025, 'twister');
    names = {'noise', 'single', 'corner', 'cross', 'parallel'};
    multiplicities = [1, 3, 5];
    noiseRatios = [0, 0.25, 0.5];
    rotations = 0:15:165;
    samples = struct('Case', {}, 'Multiplicity', {}, 'NoiseRatio', {}, ...
        'Rotation', {}, 'Opening', {}, 'Repeat', {}, 'Points', {}, ...
        'Models', {}, 'Support', {});
    for c = 1:numel(names)
        openings = 90;
        if c == 3, openings = [60, 90, 120]; end
        if c == 4, openings = [30, 60, 90]; end
        ratios = noiseRatios;
        if c == 1, ratios = 1; end
        for m = multiplicities
            for noiseRatio = ratios
                for rotation = rotations
                    for opening = openings
                        for repeat = 1:5
                            [points, models, support] = localSample(names{c}, ...
                                m, noiseRatio, rotation, opening);
                            samples(end+1) = struct('Case', names{c}, ...
                                'Multiplicity', m, 'NoiseRatio', noiseRatio, ...
                                'Rotation', rotation, 'Opening', opening, ...
                                'Repeat', repeat, 'Points', points, ...
                                'Models', models, 'Support', {support});
                        end
                    end
                end
            end
        end
    end
    save(fullfile(outputFolder, 'local_samples.mat'), 'samples');
    variants = {'Full', 'Initial RANSAC', 'Inlier ratio only'};
    tolerances = [10, 0.75; 15, 1; 20, 1.25];
    rows = cell(numel(samples)*3*3, 16);
    predictions = cell(numel(samples), 3);
    row = 0;
    for i = 1:numel(samples)
        s = samples(i);
        for v = 1:3
            options = struct('UseVerification', v ~= 2, ...
                'UseSecondVerification', v ~= 3);
            rng(2025+100000+1000*i+1, 'twister');
            [n, models] = detectLineOnEI(s.Points./[240,180], ...
                [0.5,0.5], 180, 240, false, options);
            predictions{i,v} = models;
            for k = 1:3
                matched = matchLocal(models, s.Models, s.Support, ...
                    tolerances(k,1), tolerances(k,2));
                truth = size(s.Models,1);
                exact = n == truth && matched == truth;
                row = row+1;
                rows(row,:) = {i, s.Case, s.Multiplicity, s.NoiseRatio, ...
                    s.Rotation, s.Opening, s.Repeat, variants{v}, ...
                    tolerances(k,1), tolerances(k,2), truth, n, matched, ...
                    double(exact), double(n==truth), double(n>0)};
            end
        end
        if mod(i,100)==0, fprintf('Local neighborhoods: %d/%d\n', i, numel(samples)); end
    end
    detail = cell2table(rows, 'VariableNames', {'Sample', 'Case', ...
        'Multiplicity', 'NoiseRatio', 'Rotation', 'Opening', 'Repeat', ...
        'Variant', 'AngleTolerance', 'DistanceTolerance', 'TrueLines', ...
        'PredictedLines', 'MatchedLines', 'ExactRecovery', 'CountCorrect', 'Accepted'});
    writetable(detail, fullfile(outputFolder, 'local_verification_detail.csv'));
    save(fullfile(outputFolder, 'local_verification_results.mat'), ...
        'detail', 'predictions', 'tolerances', '-v7.3');
end

function [points, models, support] = localSample(name, multiplicity, noiseRatio, rotation, opening)
    center = [120,90];
    models = zeros(0,3); support = {};
    [x,y] = meshgrid(-5:5,-4:4);
    pixels = [x(:),y(:)];
    pixels = pixels(sum((pixels./[240,180]).^2,2) <= 0.02^2,:);
    if strcmp(name,'noise')
        points = pixels(randi(size(pixels,1), 24*multiplicity, 1),:) + center;
        return;
    end
    theta = rotation*pi/180;
    directions = [cos(theta),sin(theta)];
    offsets = [0,0];
    spans = [-6,6];
    if strcmp(name,'corner') || strcmp(name,'cross')
        theta2 = theta+opening*pi/180;
        directions(2,:) = [cos(theta2),sin(theta2)];
        offsets(2,:) = [0,0];
        spans(2,:) = [-6,6];
        if strcmp(name,'corner'), spans(:,:) = repmat([0,6],2,1); end
    elseif strcmp(name,'parallel')
        directions(2,:) = directions(1,:);
        normal = [-sin(theta),cos(theta)];
        offsets = [-1.5*normal; 1.5*normal];
        spans(2,:) = [-6,6];
    end
    linePixels = zeros(0,2);
    for j = 1:size(directions,1)
        t = (spans(j,1):0.05:spans(j,2))';
        p = round(t*directions(j,:)+offsets(j,:));
        p = unique(p,'rows');
        p = p(sum((p./[240,180]).^2,2) <= 0.02^2,:);
        normal = [-directions(j,2),directions(j,1)];
        models(j,:) = [normal, -normal*(center+offsets(j,:))'];
        support{j} = p+center;
        linePixels = [linePixels; p];
    end
    linePixels = unique(linePixels,'rows');
    points = repelem(linePixels,multiplicity,1);
    noiseNum = round(noiseRatio*size(points,1));
    points = [points; pixels(randi(size(pixels,1),noiseNum,1),:)]+center;
end

function count = matchLocal(predicted, truth, support, angleTolerance, distanceTolerance)
    count = 0;
    if isempty(predicted) || isempty(truth), return; end
    pairs = false(size(predicted,1),size(truth,1));
    for i = 1:size(predicted,1)
        p = predicted(i,:)/norm(predicted(i,1:2));
        for j = 1:size(truth,1)
            cosine = min(1,abs(p(1:2)*truth(j,1:2)'));
            angle = acosd(cosine);
            residual = support{j}*p(1:2)'+p(3);
            pairs(i,j) = angle <= angleTolerance && ...
                sqrt(mean(residual.^2)) <= distanceTolerance;
        end
    end
    if any(pairs(:)), count = 1; end
    if all(size(pairs)==[2,2]) && ...
            ((pairs(1,1)&&pairs(2,2)) || (pairs(1,2)&&pairs(2,1)))
        count = 2;
    end
end
