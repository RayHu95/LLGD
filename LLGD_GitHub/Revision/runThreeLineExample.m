function detail = runThreeLineExample()
    root = fileparts(fileparts(mfilename('fullpath')));
    addpath(fullfile(root,'LineDetection'));
    outputFolder = fullfile(root,'Revision','results','three_line');
    if ~exist(outputFolder,'dir'), mkdir(outputFolder); end
    center = [120,90]; angles = [0,60,120]; multiplicity = 3;
    support = cell(3,1); truth = zeros(3,3); pixels = [];
    for j = 1:3
        direction = [cosd(angles(j)),sind(angles(j))];
        p = unique(round((-6:0.05:6)'*direction),'rows');
        p = p(sum((p./[240,180]).^2,2)<=0.02^2,:);
        support{j} = p+center;
        normal = [-direction(2),direction(1)];
        truth(j,:) = [normal,-normal*center'];
        pixels = [pixels;p];
    end
    pixels = unique(pixels,'rows')+center;
    points = repelem(pixels,multiplicity,1);
    seeds = (2025:2029)'; predictions = cell(length(seeds),1);
    assignments = cell(length(seeds),1);
    returned = zeros(length(seeds),1); matched = returned;
    angleError = cell(length(seeds),1); distanceError = angleError;
    for i = 1:length(seeds)
        rng(seeds(i),'twister');
        [returned(i),models,assignments{i}] = detectLineOnEI( ...
            points./[240,180],[0.5,0.5],180,240,false);
        predictions{i} = models;
        angle = zeros(size(models,1),3); distance = angle;
        for k = 1:size(models,1)
            model = models(k,:)/norm(models(k,1:2));
            for j = 1:3
                angle(k,j) = acosd(min(1,abs(model(1:2)*truth(j,1:2)')));
                residual = support{j}*model(1:2)'+model(3);
                distance(k,j) = sqrt(mean(residual.^2));
            end
        end
        valid = angle<=15 & distance<=1;
        matched(i) = any(valid(:));
        if size(models,1)==2
            for j = 1:3
                for k = 1:3
                    if j~=k && valid(1,j) && valid(2,k), matched(i) = 2; end
                end
            end
        end
        angleError{i} = angle; distanceError{i} = distance;
    end
    detail = table(seeds,returned,matched,'VariableNames', ...
        {'Seed','ReturnedLines','MatchedLines'});
    writetable(detail,fullfile(outputFolder,'three_line_results.csv'));
    save(fullfile(outputFolder,'three_line_results.mat'),'points','support', ...
        'truth','angles','multiplicity','predictions','assignments', ...
        'angleError','distanceError','detail');

    figure('Visible','off','Color','w','Units','centimeters','Position',[2,2,16,6]);
    colors = [0.78,0.12,0.12;0,0.32,0.7;0.1,0.55,0.25];
    for panel = 1:2
        subplot(1,2,panel); hold on;
        scatter(pixels(:,1)-120,pixels(:,2)-90,8+8*multiplicity, ...
            [0.35,0.35,0.35],'filled');
        if panel==1, models = truth; else, models = predictions{1}; end
        for j = 1:size(models,1)
            a = models(j,1); b = models(j,2); d = models(j,3)+120*a+90*b;
            if panel==1
                direction = [-b,a]; span = (support{j}-center)*direction';
                endpoints = [min(span);max(span)]*direction-d*[a,b];
                x = endpoints(:,1); y = endpoints(:,2);
            elseif abs(b)>=abs(a)
                x = [-5,5]; y = -(a*x+d)/b;
            else
                y = [-4,4]; x = -(b*y+d)/a;
            end
            plot(x,y,'Color',colors(j,:),'LineWidth',1.2);
        end
        axis equal; xlim([-5,5]); ylim([-4,4]);
        set(gca,'FontName','Times New Roman','FontSize',10,'Box','on', ...
            'XTick',[-4,0,4],'YTick',[-3,0,3]);
        xlabel('u (pixel)'); ylabel('v (pixel)');
        if panel==1, title('(a) Three imposed lines');
        elseif returned(1)==1, title('(b) Full module: 1 line');
        else, title(sprintf('(b) Full module: %d lines',returned(1))); end
    end
    set(gcf,'PaperUnits','centimeters','PaperSize',[16,6],'PaperPosition',[0,0,16,6]);
    print(gcf,fullfile(outputFolder,'ThreeLineExample.pdf'),'-dpdf','-painters');
    close(gcf);
    fprintf('%d pixels, %d events\n',size(pixels,1),size(points,1));
    disp(detail);
end
