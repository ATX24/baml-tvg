package com.example;

import static baml_client.Functions.B;

import com.boundaryml.baml.BamlStream;

import java.util.concurrent.CompletableFuture;

/**
 * Minimal BAML Java (Maven) example.
 *
 * Prerequisites:
 *   1. Build libbaml_cffi:
 *        cd ../../engine && cargo build --release -p baml_cffi
 *   2. Set environment variables:
 *        export BAML_LIBRARY_PATH=/path/to/libbaml_cffi.so   # or .dylib / .dll
 *        export GOOGLE_API_KEY=...
 *   3. Install baml-runtime-java to local Maven repo:
 *        cd ../../engine/language_client_java && mvn install
 *   4. Generate the baml_client from baml_src:
 *        baml-cli generate --from baml_src
 *   5. Run:
 *        mvn compile exec:java -Dexec.mainClass=com.example.Main
 */
public class Main {
    public static void main(String[] args) throws Exception {
        String text = "The report revised down job figures from December and January. Figures in December went down by 65,000, from 48,000 job gains to 17,000 losses. January saw a much smaller drop, revised down by 4,000 jobs, from 130,000 to 126,000. January's job report also included revisions that brought down the total number of jobs added to the economy in 2025 to 181,000 jobs -- the weakest year of job growth since Covid and a substantial decrease from the 2m jobs added to the US economy in 2024. And the job growth in 2025 was concentrated in the first half of the year: from July to December 2025, the US economy lost 45,000 jobs. The job losses were broadly based. Healthcare jobs saw a huge swing down in February, going from 77,000 new jobs in January to 28,000 losses in February. Physician offices lost 37,000 jobs primarily due to strike activity. The information sector, which includes media and telecommunications, and transportation and warehousing trended down 11,000 each. Federal government employment also continued to decline, dropping 10,000 last month. After reaching a peak in October 2024, federal government employment is down 11%, or 330,000 workers. And while the unemployment rate has remained stable, the Black unemployment rate has remained high. Last year, the rate jumped from 6.2% in January 2025 to 8.2% in November, before decreasing to 7.7% in February. In comparison, the White unemployment rate has remained steady and below the national average at 3.7%. \"The job market is struggling in the face of so many headwinds. Companies are cautious to hire and some industries are doing layoffs. The February jobs report was dismal with heavy job losses, even in healthcare, and a rise in the unemployment rate,\" said Heather Long, chief economist at Navy federal credit union. Long noted that the US economy has essentially added no jobs since last April, when Trump announced his slate of tariffs. \"Almost every major sector of the economy has been shedding jobs. Even healthcare, the one bright spot had a weak February, though that is attributed to strike activity,\" she said. Because the data from the Bureau of Labor Statistics released on Friday is solely focused on jobs in February, it does not capture the global shock waves caused by the US-Israel conflict with Iran. But the new jobs data will be influential in shaping the US Federal Reserve's upcoming meeting over interest rates on 17 and 18 March. It's unclear where Fed officials will land on interest rates, though some seem cautious about making any changes. Ahead of the meeting, Beth M Hammack, president of the Federal Reserve Bank of Cleveland, called for an extended pause of interest rates amid concerns about inflation, even though Trump has been pushing to lower them.";

        // --- Blocking call ---
        System.out.println("=== Blocking call ===");
        String summary = B.Summarize(text);
        System.out.println("Summary: " + summary);

        // --- Async call ---
        System.out.println("\n=== Async call ===");
        CompletableFuture<String> future = B.SummarizeAsync(text);
        CompletableFuture<Void> asyncDone = future.thenAccept(result ->
            System.out.println("Async result: " + result)
        );

        // --- Streaming call ---
        System.out.println("\n=== Streaming call ===");
        BamlStream<String, String> stream = B.SummarizeStream(text);
        System.out.print("Partial: ");
        for (String chunk : stream) {
            System.out.print(chunk);
            System.out.flush();
        }
        System.out.println();

        // getFinalResultAsync() -- non-blocking way to get the final streamed value
        CompletableFuture<String> streamFinal = stream.getFinalResultAsync();
        streamFinal.thenAccept(r -> System.out.println("Stream final (async): " + r));

        // Wait for both async operations before exiting
        CompletableFuture.allOf(asyncDone, streamFinal).join();
    }
}
