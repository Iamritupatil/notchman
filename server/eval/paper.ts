/**
 * A long, dense text: a 10-page research paper (fictional study, made up for
 * this test). The facts are what a student would need to answer exam
 * questions about it without reading it: the question, method, main results
 * with their numbers, the subgroup finding, limitations and the conclusion.
 */
import type { EvalCase } from "./cases.js";

const text = `Spaced retrieval practice and long-term retention in undergraduate pharmacology: a multi-site randomised controlled trial

Ananya Rao, Daniel Okafor, Meera Krishnan, Thomas Lindqvist

Abstract

Background. Laboratory studies show that retrieving information from memory, spread out over time, produces better long-term retention than re-reading the same material. Whether this holds for a full university course, with real exams and students who choose how much to engage, is less clear.

Methods. We ran a parallel-group randomised controlled trial in second-year pharmacology courses at three universities during one 12-week term. A total of 412 students were randomly assigned to a spaced retrieval practice app (n = 206) or to a control app that showed the same content as summaries to re-read (n = 206). The primary outcome was the score on the cumulative 60-item final exam in week 12. The main secondary outcome was a retention test with new questions six months after the course ended.

Results. Students in the retrieval group scored 74.3% on the final exam, against 66.1% in the re-reading group, a difference of 8.2 percentage points (95% CI 5.6 to 10.8; p < 0.001; Cohen's d = 0.52). Six months later the difference had grown: 58.7% against 44.9%, a difference of 13.8 points (95% CI 10.1 to 17.5; d = 0.71). The course pass rate was 91% against 82%. The benefit was largest for students with the lowest prior grades. Retrieval practice did not increase test anxiety.

Conclusions. Spaced retrieval practice delivered through a simple app improved exam performance and, even more, retention six months later, at the cost of about 18 extra minutes of study a week. Universities should consider building it into courses, particularly for students who start with weaker grades.

1. Introduction

Students forget most of what they learn surprisingly quickly. Classic work on the forgetting curve suggests that, without review, a large share of newly learned material is lost within days. For subjects that build on themselves, such as pharmacology, where later topics assume students remember earlier drug classes, mechanisms and side effects, this forgetting is costly. Students who forget the autonomic nervous system by week 6 struggle with cardiovascular drugs in week 9.

Two findings from cognitive psychology offer a remedy. The first is the testing effect, also called retrieval practice: actively recalling information, for example by answering a question without looking at the notes, strengthens memory more than reading the same information again. The second is the spacing effect: practice spread out over days or weeks produces more durable learning than the same amount of practice crammed into a single session. Combining the two, spaced retrieval practice asks learners to recall material at gradually increasing intervals.

The evidence for both effects is strong in the laboratory. However, most studies share three features that limit how far they apply to real courses. First, they usually test simple material such as word lists or short passages, not a full semester of complex content. Second, retention is usually measured after days or a few weeks, rarely months. Third, participants in laboratory studies do what they are told, whereas real students decide for themselves how much to use a study tool, and many use it far less than intended.

Classroom studies have begun to address these gaps, but most were run at a single institution, compared retrieval practice against doing nothing rather than against an equally time-consuming alternative, or relied on the course's own exams written by teachers who knew which students used the intervention.

We therefore designed a multi-site randomised controlled trial in a demanding, content-heavy course, with an active control condition that matched the time and content of the intervention, a primary outcome graded blind to group, and a follow-up six months after the course ended. We asked two questions. Does spaced retrieval practice delivered through an app improve performance on the final exam compared with re-reading the same content? And does any benefit persist, shrink or grow after six months? We also examined whether the benefit differed between students with stronger and weaker prior grades, and whether daily testing increased test anxiety, a concern often raised by teachers.

Our hypotheses, registered before the trial began, were that the retrieval group would score higher on the final exam, that the difference would be larger at six months, and that retrieval practice would not increase anxiety.

2. Methods

2.1 Design and setting

The trial was a parallel-group, two-arm randomised controlled trial run during the autumn term of the 2024 to 2025 academic year at three universities. All three taught a second-year pharmacology course of 12 weeks covering the same core syllabus: principles of pharmacokinetics and pharmacodynamics, the autonomic nervous system, cardiovascular drugs, antimicrobials, analgesics, and drugs acting on the central nervous system. The protocol and analysis plan were registered before recruitment. The ethics committees of all three universities approved the study, and all participants gave written informed consent.

2.2 Participants

All students enrolled in the course were invited during the first week. Students were eligible if they were enrolled for the first time and owned a smartphone. Students repeating the course were excluded because they had already seen the material. Of 497 eligible students, 412 agreed to take part (83%).

2.3 Randomisation

Participants were randomly assigned in a 1:1 ratio by a computer-generated sequence, stratified by university and by prior grade point average (GPA) tercile, so that each group had a similar mix of sites and prior achievement. Allocation was concealed until each student activated the app. Students could not be blinded, because they could see whether they were answering questions or reading summaries. Exam graders, however, did not know which group any student belonged to.

2.4 Intervention: spaced retrieval practice

The intervention group used an app that delivered 15 short-answer and multiple-choice questions per day, five days a week. Each question covered material already taught in lectures. After answering, students saw the correct answer and a one-sentence explanation. Questions came back on an expanding schedule: 1, 3, 7, 14 and 30 days after first being answered, and sooner if answered wrongly. A daily session took about 10 minutes. Students received one reminder notification per day, which they could switch off.

2.5 Control: re-reading

The control group used an app with the same design, schedule and notifications, which showed the same content as short summaries to read instead of questions to answer. Each daily session covered the same facts as the questions given to the intervention group on that day and was designed to take the same time. This active control means that any difference between groups reflects the act of retrieval and spacing, not simply extra contact with the material.

2.6 Outcomes

The primary outcome was the percentage score on the cumulative final exam in week 12: 60 items written by a panel of teachers from all three universities and graded blind to group. The exam covered the whole syllabus.

The main secondary outcome was a retention test six months after the end of the course, taken online under supervision: 40 new questions on the same syllabus that neither group had seen before. Other secondary outcomes were the course pass rate (a final exam score of at least 50%), self-reported study time per week, and test anxiety measured with a validated 10-item questionnaire at the start and end of the term.

2.7 Sample size

We aimed to detect a small-to-moderate effect of d = 0.3 on the final exam with 80% power at a two-sided significance level of 5%. This required 352 students. To allow for an expected 15% loss to follow-up, we set a target of 412.

2.8 Statistical analysis

All analyses followed the intention-to-treat principle: students were analysed in the group they were assigned to, regardless of how much they used the app. We used mixed-effects linear models with university as a random effect and prior GPA as a covariate. Effect sizes are reported as Cohen's d. For the six-month test, where some students did not take part, we repeated the analysis with multiple imputation as a sensitivity analysis. We also examined whether the effect differed by prior GPA tercile (an interaction test) and whether app use was associated with exam scores within the retrieval group (a dose-response analysis).

3. Results

3.1 Participants and adherence

The two groups were similar at the start. Mean age was 20.4 years, 61% of participants were women, and mean prior GPA did not differ between groups. All 412 students took the final exam, so the primary outcome had no missing data.

Use of the app varied widely. In the retrieval group, the median student completed 71% of the scheduled sessions, but 23% completed fewer than half. Use in the control group was similar (median 68%).

3.2 Primary outcome: the final exam

Students in the retrieval group scored a mean of 74.3% on the final exam, compared with 66.1% in the re-reading group. The adjusted difference was 8.2 percentage points (95% CI 5.6 to 10.8; p < 0.001), corresponding to a moderate effect size of d = 0.52. The effect was consistent across the three universities, ranging from 7.1 to 9.4 points.

3.3 Six-month retention

The six-month retention test was completed by 318 of the 412 students (77%). Students in the retrieval group scored 58.7%, against 44.9% in the re-reading group: a difference of 13.8 points (95% CI 10.1 to 17.5; d = 0.71). In other words, the gap between the groups grew after the course ended. Both groups forgot material, but the retrieval group forgot less: from the final exam to six months, its scores fell by 15.6 points, compared with 21.2 points in the re-reading group.

3.4 Pass rate, study time and anxiety

The pass rate was 91% in the retrieval group and 82% in the re-reading group. Students in the retrieval group reported studying about 18 minutes more per week than the control group (3.1 against 2.8 hours), a small difference. There was no difference in test anxiety between the groups at the end of term (p = 0.62).

3.5 Who benefited most

The benefit depended on prior achievement (interaction p = 0.004). Students in the lowest prior-GPA tercile gained 12.9 points on the final exam from retrieval practice, while those in the highest tercile gained 4.1 points. Retrieval practice therefore narrowed the gap between weaker and stronger students.

3.6 Dose-response

Within the retrieval group, students who completed more sessions scored higher: each additional 10% of scheduled sessions completed was associated with a 1.4-point higher exam score. Because students chose how much to use the app, this association does not by itself prove cause and effect, but it is consistent with the main result.

3.7 Student views

At the end of term, 64% of students in the retrieval group said they would keep using the app in other courses, while 29% found the daily notifications annoying. Several students commented that answering questions felt harder than reading but showed them what they had not understood.

4. Discussion

In this multi-site trial, spaced retrieval practice delivered through a simple app improved final exam scores by 8.2 percentage points compared with re-reading the same content, and the advantage grew to 13.8 points six months after the course. These effects are similar in size to those found in laboratory studies, which suggests that the benefits of retrieval and spacing survive the move from the laboratory to a demanding real course with real exams and voluntary use.

The growing gap at six months is important. Many study strategies that help on an exam do so by short-term familiarity that fades quickly. Retrieval practice appears instead to make memories more durable, which matters in courses whose later years build on earlier material. This fits the main explanation for the testing effect: the effort of recalling information strengthens the memory and the routes to it, whereas re-reading creates a feeling of familiarity without the same lasting benefit. Spacing adds to this by making each retrieval effortful again, because some forgetting has happened in between.

The larger benefit for students with weaker prior grades suggests that retrieval practice could help reduce achievement gaps. One possible reason is that stronger students already use effective strategies on their own, so the app adds less for them, while weaker students tend to rely on re-reading, which is the least effective approach.

The cost of the intervention was low. Students spent about 18 extra minutes a week, and hosting the app cost about $2 per student per term. Teachers needed to write a bank of questions once, which can then be reused.

4.1 Limitations

Our study has several limitations. First, students could not be blinded to their group, so expectations may have influenced effort; however, the active control matched time and content, and graders were blinded. Second, 23% of students did not take the six-month test, and dropout was higher in the control group (27%) than in the retrieval group (19%). When we filled in the missing scores with multiple imputation, the six-month difference shrank to 11.2 points but remained statistically significant. Third, an audit found that 9% of final exam items closely resembled questions in the app despite efforts to keep them separate; when these items were excluded, the exam difference was 7.5 points instead of 8.2. Fourth, all three universities were in the same country, so the results may not apply to other education systems. Fifth, study time was self-reported and may be inaccurate.

Funding came from the universities' teaching innovation fund, and the app was built by the authors' university without commercial involvement. One author, Thomas Lindqvist, is a paid consultant for an education technology company; that company had no role in the study.

4.2 Implications

For teachers, the practical recommendation is to build short, spaced retrieval sessions into courses rather than leaving revision to students, and to make sure students with weaker prior grades are encouraged to use them. For students, the message is that answering questions from memory, a little each day, beats re-reading notes, even though it feels harder. Future research should test whether the effect holds in other subjects and countries, and over several years of study.

5. Conclusion

Spaced retrieval practice through a simple app improved final exam performance by about 8 percentage points and long-term retention by about 14 points compared with re-reading the same material, with the largest gains for students who started with weaker grades and no increase in anxiety. It is a cheap, scalable change that universities can adopt now.`;

export const PAPER: EvalCase = {
  name: "Research paper (10 pages)",
  text,
  facts: [
    { fact: "compares spaced retrieval practice with re-reading", any: ["re-read", "reread", "re-reading", "rereading"] },
    { fact: "412 students", any: ["412"] },
    { fact: "three universities", any: ["three universities", "3 universities", "three sites", "three different universities", "three campuses"] },
    { fact: "12-week term", any: ["12 weeks", "12-week", "twelve weeks", "twelve-week"] },
    { fact: "randomised (an RCT)", any: ["randomi", "rct"] },
    { fact: "final exam 74.3% vs 66.1%", any: ["74.3"] },
    { fact: "difference 8.2 points", any: ["8.2"] },
    { fact: "six months 58.7% vs 44.9%", any: ["58.7", "44.9"] },
    { fact: "gap grew to 13.8 points", any: ["13.8"] },
    { fact: "pass rate 91% vs 82%", any: ["91%", "91 percent"] },
    { fact: "only ~18 extra minutes a week", any: ["18 minutes", "18 extra", "18 more"] },
    { fact: "biggest gain for weaker students (12.9 vs 4.1)", any: ["12.9", "lowest", "weaker", "lower prior", "low prior", "weakest"] },
    { fact: "no increase in test anxiety", any: ["anxiety"] },
    { fact: "more sessions, higher scores (dose-response)", any: ["1.4", "dose", "more sessions", "the more"] },
    { fact: "limitation: dropout at six months / 11.2 with imputation", any: ["11.2", "dropout", "drop out", "dropped out", "attrition", "didn't take", "did not take"] },
    { fact: "limitation: 9% exam items resembled app questions (7.5)", any: ["7.5", "resembl", "overlap", "similar to"] },
    { fact: "limitation: not blinded / one country", any: ["blind", "one country", "same country", "single country"] },
    { fact: "conflict of interest: author consults for edtech", any: ["consult", "conflict"] },
    { fact: "recommendation: build into courses", any: ["build", "courses", "curricul", "universities should"] },
  ],
};
