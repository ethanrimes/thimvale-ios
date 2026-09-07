package com.ethanrimes.thimvale

import android.Manifest
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.activity.ComponentActivity
import androidx.activity.compose.BackHandler
import androidx.activity.compose.LocalActivity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.*
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.viewmodel.compose.viewModel
import com.google.android.play.core.review.ReviewManagerFactory
import java.text.DateFormat
import java.util.Date
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext

class MainActivity : ComponentActivity() {
    private var pendingUpdates by mutableStateOf(false)

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        pendingUpdates = intent.getBooleanExtra("wikipediaUpdates", false)
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        pendingUpdates = intent.getBooleanExtra("wikipediaUpdates", false)
        enableEdgeToEdge()
        setContent {
            MaterialTheme(
                colorScheme =
                    lightColorScheme(
                        primary = Color(0xff32554a),
                        secondary = Color(0xff58695e),
                        secondaryContainer = Color(0xffe3e8df),
                        onSecondaryContainer = Color(0xff263b30),
                        background = Color(0xfff7f6f0),
                        surface = Color(0xfff7f6f0),
                        surfaceContainer = Color(0xffeeede7),
                        onSurface = Color(0xff242922),
                        onSurfaceVariant = Color(0xff667067),
                        outline = Color(0xff969e94),
                        outlineVariant = Color(0xffd5d8ce),
                    )
            ) {
                val model: AppModel = viewModel()
                LaunchedEffect(pendingUpdates) {
                    if (pendingUpdates) {
                        model.change { it.copy(tab = 2, showUpdates = true) }
                        pendingUpdates = false
                    }
                }
                Thimvale(model)
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun Thimvale(model: AppModel) {
    val state by model.ui.collectAsState()
    var settings by remember { mutableStateOf(false) }
    var history by remember { mutableStateOf(false) }
    val activity = LocalActivity.current
    LaunchedEffect(state.reviewOpportunity) {
        if (activity == null) return@LaunchedEffect
        val prefs = model.library.state.read()
        @Suppress("DEPRECATION")
        val fromPlay =
            activity.packageManager.getInstallerPackageName(activity.packageName) ==
                "com.android.vending"
        if (
            state.reviewOpportunity > 0 &&
                ReviewPolicy.eligible(
                    System.currentTimeMillis(),
                    prefs.optLong("firstUse"),
                    prefs.optInt("interactions"),
                    prefs.optLong("reviewRequested"),
                    prefs.optString("reviewVersion"),
                    BuildConfig.VERSION_NAME,
                    prefs.optBoolean("reviewEnabled", true),
                    prefs.optBoolean("reviewed"),
                    !BuildConfig.DEBUG && fromPlay,
                )
        ) {
            model.library.state.change {
                it.put("reviewRequested", System.currentTimeMillis())
                    .put("reviewVersion", BuildConfig.VERSION_NAME)
            }
            val review = ReviewManagerFactory.create(activity)
            review.requestReviewFlow().addOnSuccessListener {
                review.launchReviewFlow(activity, it)
            }
        }
    }
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("✦  thimvale", fontWeight = FontWeight.SemiBold) },
                navigationIcon = {
                    IconButton({ history = true }, enabled = !state.busy) {
                        Icon(Icons.AutoMirrored.Outlined.MenuOpen, "Conversation history")
                    }
                },
                actions = {
                    IconButton({ model.newChat() }, enabled = !state.busy) {
                        Icon(Icons.Outlined.EditNote, "New conversation")
                    }
                    IconButton({ settings = true }) { Icon(Icons.Outlined.Settings, "Settings") }
                },
            )
        },
        bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.background) {
                val icons =
                    listOf(
                        Icons.AutoMirrored.Outlined.Chat,
                        Icons.Outlined.Layers,
                        Icons.Outlined.MenuBook,
                        Icons.Outlined.BackHand,
                    )
                listOf("Chat", "Models", "Knowledge", "Permissions").forEachIndexed { index, title
                    ->
                    NavigationBarItem(
                        selected = state.tab == index,
                        onClick = { model.change { it.copy(tab = index) } },
                        icon = { Icon(icons[index], title) },
                        label = { Text(title) },
                    )
                }
            }
        },
    ) { padding ->
        Column(Modifier.fillMaxSize().padding(padding)) {
            if (state.updateCount > 0)
                TextButton(
                    { model.change { it.copy(showUpdates = true) } },
                    Modifier.fillMaxWidth(),
                ) {
                    Icon(Icons.Outlined.Update, null)
                    Spacer(Modifier.width(8.dp))
                    Text("Wikipedia updates available · ${state.updateCount}")
                }
            Box(Modifier.weight(1f)) {
                when (state.tab) {
                    0 -> ChatScreen(model, state)
                    1 -> ModelsScreen(model, state)
                    2 -> KnowledgeScreen(model, state)
                    else -> PermissionsScreen(model, state)
                }
            }
        }
    }
    if (settings) FullScreen("Settings", { settings = false }) { SettingsScreen(model, state) }
    if (history)
        FullScreen("Conversations", { history = false }) {
            LazyColumn {
                items(model.history()) { (id, title) ->
                    TextButton(
                        {
                            model.openChat(id)
                            history = false
                        },
                        Modifier.fillMaxWidth(),
                    ) {
                        Text(title, Modifier.fillMaxWidth().padding(12.dp))
                    }
                }
            }
        }
    if (state.showUpdates)
        FullScreen("Wikipedia updates", { model.change { it.copy(showUpdates = false) } }) {
            UpdatesScreen(model, state)
        }
    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = { model.change { it.copy(error = null) } },
            title = { Text("Couldn't finish") },
            text = { Text(message) },
            confirmButton = {
                TextButton({ model.change { it.copy(error = null) } }) { Text("OK") }
            },
        )
    }
    state.approval?.let { approval ->
        AlertDialog(
            onDismissRequest = { approval.result.complete(false) },
            title = { Text(approval.call.capability.title) },
            text = {
                Column(Modifier.verticalScroll(rememberScrollState()).heightIn(max = 420.dp)) {
                    Text(
                        if (approval.call.capability == Capability.WEB)
                            "This query will be sent to Brave Search."
                        else "Allow this tool call once?"
                    )
                    Spacer(Modifier.height(12.dp))
                    Text(
                        approval.call.args.toString(2),
                        fontFamily = FontFamily.Monospace,
                        fontSize = 13.sp,
                    )
                }
            },
            confirmButton = {
                TextButton({ approval.result.complete(true) }) { Text("Allow once") }
            },
            dismissButton = {
                TextButton({ approval.result.complete(false) }) { Text("Don't allow") }
            },
        )
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun FullScreen(title: String, close: () -> Unit, content: @Composable () -> Unit) {
    Dialog(
        onDismissRequest = close,
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(Modifier.fillMaxSize()) {
            Column(Modifier.safeDrawingPadding()) {
                TopAppBar(
                    title = { Text(title, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                    navigationIcon = {
                        IconButton(close) { Icon(Icons.AutoMirrored.Outlined.ArrowBack, "Back") }
                    },
                )
                Box(Modifier.weight(1f)) { content() }
            }
        }
    }
}

@Composable
fun Subtitle(text: String) {
    Text(
        text,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        style = MaterialTheme.typography.bodySmall,
    )
}

@Composable
fun Section(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column(
        Modifier.fillMaxWidth().padding(vertical = 10.dp),
        verticalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Text(title, style = MaterialTheme.typography.titleMedium)
        content()
    }
}

@Composable
fun ChatScreen(model: AppModel, state: ScreenState) {
    val list = rememberLazyListState()
    var evidence by remember { mutableStateOf<Evidence?>(null) }
    LaunchedEffect(state.messages.lastOrNull()?.text, state.messages.lastOrNull()?.events) {
        if (state.messages.isNotEmpty()) list.scrollToItem(state.messages.lastIndex)
    }
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            FilterChip(
                !state.work,
                { if (!state.busy) model.change { it.copy(work = false) } },
                { Text("Chat") },
            )
            Spacer(Modifier.width(8.dp))
            FilterChip(
                state.work,
                { if (!state.busy) model.change { it.copy(work = true) } },
                { Text("Work") },
            )
            Spacer(Modifier.weight(1f))
            TextButton({ model.change { it.copy(tab = 1) } }) {
                Text(
                    if (state.selected.isBlank()) "Choose model"
                    else state.selected.substringAfter('-').take(22),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
        }
        Subtitle(state.runtime)
        if (state.messages.isEmpty())
            Column(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.Center) {
                Text(
                    if (state.work) "What are you working on?" else "What's on your mind?",
                    fontFamily = FontFamily.Serif,
                    fontSize = 30.sp,
                )
                Spacer(Modifier.height(12.dp))
                Text(
                    if (state.work)
                        "Search your knowledge and use tools with the permissions you choose."
                    else "Choose a downloaded model to start a conversation.",
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        else
            LazyColumn(
                state = list,
                modifier = Modifier.weight(1f),
                contentPadding = PaddingValues(vertical = 20.dp),
                verticalArrangement = Arrangement.spacedBy(24.dp),
            ) {
                items(state.messages, key = { it.id }) { message ->
                    if (message.role == "user")
                        Surface(
                            color = MaterialTheme.colorScheme.surfaceContainer,
                            shape = RoundedCornerShape(22.dp),
                        ) {
                            Text(message.text, Modifier.padding(18.dp), fontSize = 17.sp)
                        }
                    else
                        Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
                            Subtitle("✦  THIMVALE")
                            message.events.forEach { ToolRow(it) }
                            AnswerText(message.text, message.sources) { evidence = it }
                            if (!state.busy && message.sources.isNotEmpty()) {
                                val references =
                                    Regex("\\[([0-9]+)]")
                                        .findAll(message.text)
                                        .map { it.groupValues[1] }
                                        .toSet()
                                val known = message.sources.map { it.id }.toSet()
                                if (references.isEmpty())
                                    Subtitle("This answer didn't include source references.")
                                else if ((references - known).isNotEmpty())
                                    Subtitle("Some references don't match the retrieved sources.")
                            }
                            if (message.raw.isNotBlank())
                                Expandable("Model details") {
                                    Text(
                                        message.raw,
                                        fontFamily = FontFamily.Monospace,
                                        fontSize = 12.sp,
                                        modifier =
                                            Modifier.heightIn(max = 240.dp)
                                                .verticalScroll(rememberScrollState()),
                                    )
                                }
                            if (message.sources.isNotEmpty())
                                Expandable("Sources ${message.sources.size}") {
                                    message.sources.forEach { source ->
                                        TextButton(
                                            { evidence = source },
                                            contentPadding = PaddingValues(0.dp),
                                        ) {
                                            Text(
                                                "[${source.id}] ${source.title}",
                                                Modifier.fillMaxWidth(),
                                            )
                                        }
                                    }
                                }
                            if (message.id == state.messages.last().id && state.busy)
                                Row(verticalAlignment = Alignment.CenterVertically) {
                                    CircularProgressIndicator(
                                        Modifier.size(14.dp),
                                        strokeWidth = 2.dp,
                                    )
                                    Spacer(Modifier.width(8.dp))
                                    Subtitle("Generating…")
                                }
                        }
                }
            }
        Row(Modifier.imePadding().padding(vertical = 8.dp), verticalAlignment = Alignment.Bottom) {
            OutlinedTextField(
                state.draft,
                { text -> model.change { it.copy(draft = text) } },
                Modifier.weight(1f),
                placeholder = { Text(if (state.work) "Describe a task" else "Message") },
                shape = RoundedCornerShape(25.dp),
                maxLines = 6,
            )
            IconButton(
                { if (state.busy) model.stop() else model.send() },
                Modifier.padding(start = 6.dp),
            ) {
                Icon(
                    if (state.busy) Icons.Outlined.StopCircle else Icons.AutoMirrored.Outlined.Send,
                    if (state.busy) "Stop generation" else "Send message",
                    tint = MaterialTheme.colorScheme.primary,
                )
            }
        }
        Subtitle(
            if (state.work) "Tools follow your permissions. Web search uses the internet."
            else "Your conversation stays on this phone."
        )
    }
    evidence?.let { source ->
        FullScreen("Evidence", { evidence = null }) {
            Column(
                Modifier.padding(22.dp).verticalScroll(rememberScrollState()),
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Text(source.title, style = MaterialTheme.typography.headlineSmall)
                Subtitle(source.location)
                Text(source.text)
                if (source.url.startsWith("https://"))
                    BrowserLink("Open original source", source.url)
            }
        }
    }
}

@Composable
fun Expandable(
    title: String,
    monospace: Boolean = false,
    content: @Composable ColumnScope.() -> Unit,
) {
    var open by remember { mutableStateOf(false) }
    Column {
        Row(
            Modifier.fillMaxWidth().clickable { open = !open }.padding(vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (open) "⌄" else "›", Modifier.width(20.dp))
            Text(
                title,
                fontFamily = if (monospace) FontFamily.Monospace else FontFamily.Default,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        if (open) Column(Modifier.padding(start = 20.dp), content = content)
    }
}

@Composable
fun ToolRow(event: ToolEvent) {
    Expandable(
        "${if (event.state == "Completed") "✓" else if (event.state == "Failed") "×" else "·"} ${event.name}  ·  ${event.state}",
        monospace = true,
    ) {
        Text(event.input, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
        if (event.output.isNotEmpty())
            Text(
                event.output,
                Modifier.heightIn(max = 200.dp).verticalScroll(rememberScrollState()),
                fontFamily = FontFamily.Monospace,
                fontSize = 12.sp,
            )
    }
}

@Composable
fun AnswerText(text: String, sources: List<Evidence>, open: (Evidence) -> Unit) {
    val color = MaterialTheme.colorScheme.primary
    val annotated = buildAnnotatedString {
        var position = 0
        Regex("\\[([0-9]+)]").findAll(text).forEach { match ->
            append(text.substring(position, match.range.first))
            val source = sources.firstOrNull { it.id == match.groupValues[1] }
            if (source != null)
                withLink(
                    LinkAnnotation.Clickable(
                        source.id,
                        TextLinkStyles(
                            style = SpanStyle(color = color, fontWeight = FontWeight.SemiBold)
                        ),
                    ) {
                        open(source)
                    }
                ) {
                    append(match.value)
                }
            else append(match.value)
            position = match.range.last + 1
        }
        append(text.substring(position))
    }
    Text(annotated, fontSize = 17.sp, lineHeight = 26.sp)
}

@Composable
fun ModelsScreen(model: AppModel, state: ScreenState) {
    var query by remember { mutableStateOf("") }
    var filter by remember { mutableStateOf("All") }
    var hubResults by remember { mutableStateOf<List<Model>>(emptyList()) }
    var searching by remember { mutableStateOf(false) }
    var selected by remember { mutableStateOf<Model?>(null) }
    val imported =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) model.runTask { model.knowledge.importLibrary(uri) }
        }
    Column(Modifier.fillMaxSize().padding(horizontal = 18.dp)) {
        OutlinedTextField(
            query,
            { query = it },
            Modifier.fillMaxWidth(),
            placeholder = { Text("Search models or owner/repository") },
            singleLine = true,
        )
        Row(
            Modifier.horizontalScroll(rememberScrollState()),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            listOf("All", "4B", "Downloaded", "Hugging Face").forEach { choice ->
                FilterChip(filter == choice, { filter = choice }, { Text(choice) })
            }
        }
        Row {
            TextButton({ imported.launch(arrayOf("*/*")) }) { Text("Import GGUF") }
            if (filter == "Hugging Face")
                TextButton(
                    {
                        model.runTask {
                            searching = true
                            try {
                                hubResults = model.network.searchModels(query)
                            } finally {
                                searching = false
                            }
                        }
                    },
                    enabled = !searching && query.isNotBlank(),
                ) {
                    Text(if (searching) "Searching…" else "Search Hugging Face")
                }
        }
        LazyColumn(verticalArrangement = Arrangement.spacedBy(6.dp)) {
            if (filter == "Downloaded") {
                val files = model.library.files("gguf")
                if (files.isEmpty())
                    item { Text("No models downloaded yet.", Modifier.padding(vertical = 24.dp)) }
                items(files, key = { it.name }) { file ->
                    Column(Modifier.fillMaxWidth().padding(vertical = 10.dp)) {
                        Text(file.name.substringAfter('-'), fontWeight = FontWeight.Medium)
                        Subtitle(
                            android.text.format.Formatter.formatFileSize(
                                LocalContext.current,
                                file.length(),
                            )
                        )
                        TextButton({ model.select(file.name) }, enabled = !state.busy) {
                            Text(
                                if (state.selected == file.name) "Selected · ${state.runtime}"
                                else "Use model"
                            )
                        }
                        DeleteFileButton(model, file, state)
                    }
                }
            } else {
                val models =
                    if (filter == "Hugging Face") hubResults
                    else
                        model.library.models.filter {
                            (filter != "4B" || it.fourB) &&
                                (query.isBlank() ||
                                    "${it.name} ${it.family} ${it.parameters} ${it.summary}"
                                        .contains(query, true))
                        }
                if (models.isEmpty())
                    item {
                        Text(
                            if (filter == "Hugging Face")
                                "Search online for single-file GGUF repositories."
                            else "No matching models.",
                            Modifier.padding(vertical = 24.dp),
                        )
                    }
                items(models, key = { it.id }) { entry ->
                    Column(
                        Modifier.fillMaxWidth()
                            .clickable { selected = entry }
                            .padding(vertical = 14.dp),
                        verticalArrangement = Arrangement.spacedBy(5.dp),
                    ) {
                        Row {
                            Text(
                                entry.name,
                                fontWeight = FontWeight.SemiBold,
                                modifier = Modifier.weight(1f),
                            )
                            Text(entry.parameters, color = MaterialTheme.colorScheme.primary)
                        }
                        Subtitle(
                            "${entry.family} · ${if (entry.memory > 0) "${entry.memory} GB RAM guidance" else "Check available memory"}"
                        )
                        Text(entry.summary, style = MaterialTheme.typography.bodyMedium)
                        HorizontalDivider(
                            Modifier.padding(top = 12.dp),
                            color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = .4f),
                        )
                    }
                }
            }
        }
    }
    selected?.let { entry ->
        FullScreen(entry.name, { selected = null }) { ModelFiles(model, entry) }
    }
}

@Composable
fun ModelFiles(model: AppModel, entry: Model) {
    var files by remember { mutableStateOf<List<RemoteFile>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(true) }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(entry.repository, retry) {
        loading = true
        error = null
        try {
            files = model.network.modelFiles(entry.repository)
        } catch (e: Exception) {
            error = e.message
        } finally {
            loading = false
        }
    }
    LazyColumn(
        Modifier.padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Text(entry.summary)
            Spacer(Modifier.height(12.dp))
            BrowserLink("Model card and license", "https://huggingface.co/${entry.repository}")
            Subtitle(
                "Choose a quantization that fits your free memory. CPU inference speed varies by phone; large weights may not load."
            )
        }
        if (loading) item { LinearProgressIndicator(Modifier.fillMaxWidth()) }
        error?.let { message ->
            item {
                Text(message)
                TextButton({ retry++ }) { Text("Retry") }
            }
        }
        items(files, key = { it.name }) { file -> DownloadRow(model, file) }
    }
}

@Composable
fun DownloadRow(model: AppModel, file: RemoteFile) {
    val current by model.ui.collectAsState()
    val installed = remember(current.revision, file.name) { model.library.file(file.name).exists() }
    var confirm by remember { mutableStateOf(false) }
    var queueing by remember { mutableStateOf(false) }
    val size = android.text.format.Formatter.formatFileSize(LocalContext.current, file.bytes)
    Column(Modifier.padding(vertical = 6.dp)) {
        Text(file.title, fontWeight = FontWeight.Medium)
        Subtitle("$size · ${file.license.ifBlank { "See model card for license" }}")
        TextButton({ confirm = true }, enabled = !queueing && !installed) {
            Text(if (queueing) "Preparing…" else if (installed) "Installed" else "Download")
        }
    }
    if (confirm)
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Download $size?") },
            text = {
                Text(
                    "${file.title}\n\n${file.license.ifBlank { "Review the publisher's license before downloading." }}\n\nThis uses device storage. Pack updates keep the previous edition; they are full downloads, not small patches."
                )
            },
            confirmButton = {
                TextButton({
                    confirm = false
                    model.runTask {
                        queueing = true
                        try {
                            model.downloads.enqueue(model.network.verifiedDownload(file))
                        } finally {
                            queueing = false
                        }
                    }
                }) {
                    Text("Download")
                }
            },
            dismissButton = { TextButton({ confirm = false }) { Text("Cancel") } },
        )
}

@Composable
fun KnowledgeScreen(model: AppModel, state: ScreenState) {
    val folders = model.knowledge.folders()
    var catalog by remember { mutableStateOf(false) }
    var reader by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var results by remember { mutableStateOf<List<Evidence>>(emptyList()) }
    var status by remember { mutableStateOf("") }
    val connect =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocumentTree()) { uri ->
            if (uri != null)
                model.runTask { withContext(Dispatchers.IO) { model.knowledge.connect(uri) } }
        }
    val imported =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri != null) model.runTask { model.knowledge.importLibrary(uri) }
        }
    LazyColumn(
        Modifier.fillMaxSize().padding(horizontal = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        item {
            Section("Offline Wikipedia") {
                Text("Browse downloaded articles without a model.")
                Row {
                    TextButton({ catalog = true }) { Text("Download packs") }
                    TextButton({ imported.launch(arrayOf("*/*")) }) { Text("Import ZIM") }
                }
                TextButton({ model.change { it.copy(showUpdates = true) } }) {
                    Text("Check pack updates")
                }
            }
        }
        items(model.library.files("zim"), key = { it.name }) { file ->
            Column {
                TextButton({ reader = file.name }) {
                    Icon(Icons.Outlined.MenuBook, null)
                    Spacer(Modifier.width(8.dp))
                    Text(file.name)
                }
                DeleteFileButton(model, file, state)
            }
        }
        item {
            Section("Connected folders") {
                Text(
                    "Only folders you choose are available. Android's private app folders aren't exposed by the system picker."
                )
                TextButton({ connect.launch(null) }) { Text("Connect folder") }
                Subtitle(
                    "Indexing supports UTF-8 text, Markdown, CSV, JSON and HTML. Create files and read files have separate tool permissions."
                )
            }
        }
        items(folders, key = { it.id }) { folder ->
            Column {
                Text(folder.name, fontWeight = FontWeight.Medium)
                Subtitle("Folder ID: ${folder.id}")
                Row {
                    TextButton({
                        model.runTask {
                            status = "Indexing…"
                            status = model.knowledge.indexFolder(folder.id)
                        }
                    }) {
                        Text("Index text")
                    }
                    TextButton({ model.runTask { model.knowledge.disconnect(folder.id) } }) {
                        Text("Disconnect")
                    }
                }
            }
        }
        if (status.isNotBlank()) item { Subtitle(status) }
        item {
            Section("Search knowledge") {
                OutlinedTextField(
                    query,
                    { query = it },
                    Modifier.fillMaxWidth(),
                    label = { Text("Search local text") },
                    singleLine = true,
                )
                TextButton(
                    {
                        model.runTask {
                            results =
                                withContext(Dispatchers.IO) {
                                    model.knowledge.search(query) + model.wikipedia.search(query)
                                }
                            status = "${results.size} results"
                        }
                    },
                    enabled = query.isNotBlank(),
                ) {
                    Text("Search")
                }
            }
        }
        items(results) { source ->
            Expandable(source.title) {
                Subtitle(source.location)
                Text(source.text)
            }
        }
        val jobs = model.downloads.statuses()
        if (jobs.isNotEmpty())
            item { Text("Downloads", style = MaterialTheme.typography.titleMedium) }
        items(jobs, key = { it.id }) { job ->
            Column {
                Text(job.title)
                LinearProgressIndicator(
                    progress = { job.progress.coerceIn(0f, 1f) },
                    modifier = Modifier.fillMaxWidth(),
                )
                Subtitle(job.state)
                TextButton({
                    model.downloads.cancel(job.id)
                    model.refresh()
                }) {
                    Text("Cancel download")
                }
            }
        }
    }
    if (catalog) FullScreen("Wikipedia packs", { catalog = false }) { WikiCatalogScreen(model) }
    reader?.let { file -> FullScreen("Wikipedia", { reader = null }) { ReaderScreen(model, file) } }
}

@Composable
fun DeleteFileButton(model: AppModel, file: java.io.File, state: ScreenState) {
    var confirm by remember { mutableStateOf(false) }
    TextButton({ confirm = true }, enabled = !state.busy) { Text("Remove download") }
    if (confirm)
        AlertDialog(
            onDismissRequest = { confirm = false },
            title = { Text("Remove this download?") },
            text = {
                Text(
                    "${file.name}\n\nThe local copy will be deleted. Download or import it again to use it offline."
                )
            },
            confirmButton = {
                TextButton({
                    confirm = false
                    model.runTask {
                        if (state.selected == file.name) {
                            model.engine.release()
                            model.change { it.copy(selected = "", runtime = "No model selected") }
                            model.library.state.change { it.remove("selected") }
                        }
                        withContext(Dispatchers.IO) {
                            model.wikipedia.close()
                            check(file.delete()) { "Couldn't remove the file." }
                        }
                    }
                }) {
                    Text("Remove")
                }
            },
            dismissButton = { TextButton({ confirm = false }) { Text("Cancel") } },
        )
}

@Composable
fun WikiCatalogScreen(model: AppModel) {
    var files by remember { mutableStateOf<List<RemoteFile>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var query by remember { mutableStateOf("") }
    var retry by remember { mutableIntStateOf(0) }
    LaunchedEffect(retry) {
        try {
            files = model.network.wikipedia()
            error = null
        } catch (e: Exception) {
            error = e.message
        }
    }
    LazyColumn(Modifier.padding(20.dp)) {
        item {
            Text(
                "Mini packs are abridged. Full English text can take tens of gigabytes. Packs stay compressed and use their existing search index."
            )
            OutlinedTextField(
                query,
                { query = it },
                Modifier.fillMaxWidth().padding(vertical = 16.dp),
                placeholder = { Text("Find a topic or edition") },
            )
            error?.let {
                Text(it)
                TextButton({ retry++ }) { Text("Retry") }
            }
        }
        items(files.filter { "${it.title} ${it.name}".contains(query, true) }, key = { it.name }) {
            DownloadRow(model, it)
        }
    }
}

@Composable
fun UpdatesScreen(model: AppModel, state: ScreenState) {
    LazyColumn(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        item {
            Text(
                "New editions are checked when you reconnect while using the app. Downloads require confirmation and keep your old pack."
            )
            TextButton(
                { model.checkUpdates(manual = true) },
                enabled = !state.checkingUpdates && model.library.files("zim").isNotEmpty(),
            ) {
                Text(if (state.checkingUpdates) "Checking…" else "Check now")
            }
            val last = model.library.state.read().optLong("wikiChecked")
            if (last > 0)
                Subtitle(
                    "Last checked ${DateFormat.getDateTimeInstance(DateFormat.SHORT, DateFormat.SHORT).format(Date(last))}"
                )
            state.updateError?.let { Text(it) }
        }
        val updates = model.availableUpdates()
        if (updates.isEmpty())
            item {
                Text(
                    if (model.library.files("zim").isEmpty()) "Download a Wikipedia pack first."
                    else "No newer matching editions in the last catalog check."
                )
            }
        items(updates, key = { it.second.name }) { (old, file) ->
            Column {
                Subtitle("Installed: $old")
                DownloadRow(model, file)
            }
        }
    }
}

@Composable
fun PermissionsScreen(model: AppModel, state: ScreenState) {
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text("You choose what tools can do.", fontFamily = FontFamily.Serif, fontSize = 28.sp)
        Text(
            "Ask shows the exact tool input before it runs. Permissions are checked again after approval. File creation never overwrites existing files."
        )
        Capability.entries.forEach { capability ->
            Section(capability.title) {
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    Permission.entries.forEach { permission ->
                        FilterChip(
                            model.library.permission(capability) == permission,
                            {
                                model.library.setPermission(capability, permission)
                                model.refresh()
                            },
                            {
                                Text(
                                    when (permission) {
                                        Permission.DENY -> "Off"
                                        Permission.ASK -> "Ask"
                                        Permission.ALLOW -> "Allow"
                                    }
                                )
                            },
                        )
                    }
                }
            }
        }
        Subtitle(
            "Chat mode has no tools. Work mode can request only these capabilities; source text cannot grant permission."
        )
    }
}

@Composable
fun SettingsScreen(model: AppModel, state: ScreenState) {
    var hf by remember { mutableStateOf(model.library.secrets.get("huggingface")) }
    var brave by remember { mutableStateOf(model.library.secrets.get("brave")) }
    var saved by remember { mutableStateOf(false) }
    val notification =
        rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { allowed ->
            model.library.state.change { it.put("packNotifications", allowed) }
            model.refresh()
        }
    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Section("Downloads") {
            PreferenceToggle("Allow cellular downloads", model, "cellular")
            Subtitle(
                "Applies to new downloads. Android manages transfers after you leave the app. Force-stopping the app or system restrictions can pause downloads; verification may wait for the next launch."
            )
        }
        Section("Keys") {
            OutlinedTextField(
                hf,
                {
                    hf = it
                    saved = false
                },
                Modifier.fillMaxWidth(),
                label = { Text("Hugging Face token") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
            )
            OutlinedTextField(
                brave,
                {
                    brave = it
                    saved = false
                },
                Modifier.fillMaxWidth(),
                label = { Text("Brave Search API key") },
                visualTransformation = PasswordVisualTransformation(),
                singleLine = true,
            )
            TextButton({
                model.runTask {
                    model.library.secrets.set("huggingface", hf.trim())
                    model.library.secrets.set("brave", brave.trim())
                    saved = true
                }
            }) {
                Text(if (saved) "Saved" else "Save keys")
            }
            Subtitle(
                "Keys are encrypted with Android Keystore. Web search sends only the query you permit to Brave."
            )
        }
        Section("Notifications") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Wikipedia update alerts", Modifier.weight(1f))
                Switch(
                    model.library.state.read().optBoolean("packNotifications"),
                    { enabled ->
                        if (enabled && Build.VERSION.SDK_INT >= 33)
                            notification.launch(Manifest.permission.POST_NOTIFICATIONS)
                        else {
                            model.library.state.change { it.put("packNotifications", enabled) }
                            model.refresh()
                        }
                    },
                )
            }
            Subtitle(
                "Optional local alerts when a foreground check finds a newer pack. No push server and no review-request notifications."
            )
        }
        Section("Reviews") {
            PreferenceToggle("Allow occasional review requests", model, "reviewEnabled", true)
            PreferenceToggle("I've already reviewed", model, "reviewed")
            Subtitle(
                "Google controls whether its review sheet appears. We cannot tell whether you submitted a review. Debug builds don't request reviews."
            )
        }
        Section("About") {
            Text("Thimvale ${BuildConfig.VERSION_NAME}")
            Subtitle(
                "Native Kotlin · llama.cpp b10830 · libkiwix 2.6.0\nLocal text indexing uses compact lexical vectors and a full-text index. This Android edition does not use semantic sentence embeddings or read PDFs yet."
            )
            BrowserLink("Source code and licenses", "https://github.com/ethanrimes/thimvale-ios")
            Text(
                "GPL-3.0-or-later. Models have separate licenses. Wikipedia contributors · CC BY-SA."
            )
        }
    }
}

@Composable
fun PreferenceToggle(title: String, model: AppModel, key: String, default: Boolean = false) {
    val current by model.ui.collectAsState()
    val checked =
        remember(current.revision, key) { model.library.state.read().optBoolean(key, default) }
    Row(verticalAlignment = Alignment.CenterVertically) {
        Text(title, Modifier.weight(1f))
        Switch(
            checked,
            { value ->
                model.library.state.change { it.put(key, value) }
                model.refresh()
            },
            modifier = Modifier.semantics { contentDescription = title },
        )
    }
}

@Composable
fun BrowserLink(title: String, url: String) {
    val context = LocalContext.current
    TextButton({
        runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url))) }
    }) {
        Text(title)
    }
}

@Composable
fun ReaderScreen(model: AppModel, filename: String) {
    var query by remember { mutableStateOf("") }
    var offset by remember { mutableIntStateOf(0) }
    var entries by remember { mutableStateOf<List<ArticleEntry>>(emptyList()) }
    var stack by remember { mutableStateOf<List<String>>(emptyList()) }
    var article by remember { mutableStateOf<Article?>(null) }
    var error by remember { mutableStateOf<String?>(null) }
    var loading by remember { mutableStateOf(false) }
    var external by remember { mutableStateOf<String?>(null) }
    val context = LocalContext.current
    LaunchedEffect(query, offset, stack) {
        loading = true
        error = null
        try {
            if (stack.isEmpty()) {
                delay(200)
                entries =
                    withContext(Dispatchers.IO) { model.wikipedia.browse(filename, query, offset) }
            } else
                article =
                    withContext(Dispatchers.IO) { model.wikipedia.article(filename, stack.last()) }
        } catch (e: Exception) {
            error = e.message ?: "This page isn't included in this pack."
        } finally {
            loading = false
        }
    }
    BackHandler(stack.isNotEmpty()) { stack = stack.dropLast(1) }
    Column(Modifier.fillMaxSize()) {
        if (stack.isNotEmpty())
            TextButton({ stack = stack.dropLast(1) }) {
                Text("‹ Back to ${if (stack.size == 1) "articles" else "previous article"}")
            }
        if (loading) LinearProgressIndicator(Modifier.fillMaxWidth())
        error?.let { Text(it, Modifier.padding(20.dp)) }
        if (stack.isEmpty()) {
            OutlinedTextField(
                query,
                {
                    query = it
                    offset = 0
                },
                Modifier.fillMaxWidth().padding(horizontal = 18.dp),
                placeholder = { Text("Search this offline pack") },
                singleLine = true,
            )
            LazyColumn(Modifier.weight(1f)) {
                items(entries, key = { it.path }) { entry ->
                    TextButton({ stack = stack + entry.path }, Modifier.fillMaxWidth()) {
                        Text(
                            entry.title,
                            Modifier.fillMaxWidth().padding(12.dp),
                            color = MaterialTheme.colorScheme.onSurface,
                        )
                    }
                }
            }
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                TextButton({ offset = maxOf(0, offset - 40) }, enabled = offset > 0 && !loading) {
                    Text("Previous")
                }
                TextButton({ offset += 40 }, enabled = entries.size == 40 && !loading) {
                    Text("Next")
                }
            }
        } else if (!loading && error == null)
            article?.let { current ->
                key(current.path) {
                    AndroidView(
                        factory = { ctx ->
                            WebView(ctx).apply {
                                settings.javaScriptEnabled = false
                                settings.allowFileAccess = false
                                settings.allowContentAccess = false
                                settings.blockNetworkLoads = true
                                settings.domStorageEnabled = false
                                webViewClient =
                                    object : WebViewClient() {
                                        override fun shouldInterceptRequest(
                                            view: WebView,
                                            request: WebResourceRequest,
                                        ): WebResourceResponse =
                                            WebResourceResponse(
                                                "text/plain",
                                                "UTF-8",
                                                "".byteInputStream(),
                                            )

                                        override fun shouldOverrideUrlLoading(
                                            view: WebView,
                                            request: WebResourceRequest,
                                        ): Boolean {
                                            val uri = request.url
                                            if (
                                                uri.scheme == "https" &&
                                                    uri.host == "offline.thimvale.invalid" &&
                                                    uri.userInfo == null &&
                                                    uri.port == -1
                                            ) {
                                                val path = uri.path.orEmpty().removePrefix("/")
                                                if (path == current.path && uri.fragment != null)
                                                    return false
                                                stack = stack + path
                                            } else if (uri.scheme in listOf("http", "https"))
                                                external = uri.toString()
                                            return true
                                        }
                                    }
                                loadDataWithBaseURL(
                                    WikiHTML.url(current.path),
                                    current.html,
                                    "text/html",
                                    "UTF-8",
                                    null,
                                )
                            }
                        },
                        onRelease = {
                            it.stopLoading()
                            it.destroy()
                        },
                        modifier = Modifier.weight(1f),
                    )
                }
            }
    }
    external?.let { url ->
        AlertDialog(
            onDismissRequest = { external = null },
            title = { Text("Open this website online?") },
            text = { Text(url) },
            confirmButton = {
                TextButton({
                    external = null
                    runCatching {
                        context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
                    }
                }) {
                    Text("Open browser")
                }
            },
            dismissButton = { TextButton({ external = null }) { Text("Cancel") } },
        )
    }
}
