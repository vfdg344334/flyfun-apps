package me.zhaoqian.flyfun.ui.chat

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.text.AnnotatedString
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import kotlinx.coroutines.launch
import me.zhaoqian.flyfun.ui.theme.*
import me.zhaoqian.flyfun.viewmodel.ChatViewModel
import me.zhaoqian.flyfun.viewmodel.Role
import me.zhaoqian.flyfun.viewmodel.UiChatMessage

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ChatScreen(
    onNavigateToMap: () -> Unit,
    viewModel: ChatViewModel = hiltViewModel()
) {
    val messages by viewModel.messages.collectAsState()
    val isStreaming by viewModel.isStreaming.collectAsState()
    val currentThinking by viewModel.currentThinking.collectAsState()
    val error by viewModel.error.collectAsState()
    
    var inputText by remember { mutableStateOf("") }
    val listState = rememberLazyListState()
    val coroutineScope = rememberCoroutineScope()
    
    // Scroll to bottom when new messages arrive
    LaunchedEffect(messages.size) {
        if (messages.isNotEmpty()) {
            listState.animateScrollToItem(messages.size - 1)
        }
    }
    
    Scaffold(
        topBar = {
            TopAppBar(
                title = { 
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(12.dp)
                    ) {
                        // Airplane icon
                        Text(
                            text = "✈️",
                            style = MaterialTheme.typography.headlineMedium
                        )
                        Column {
                            Text(
                                text = "FlyFun Assistant",
                                style = MaterialTheme.typography.titleLarge
                            )
                            Text(
                                text = "Your intelligent aviation companion",
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant
                            )
                        }
                    }
                },
                navigationIcon = {
                    IconButton(onClick = onNavigateToMap) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back to Map")
                    }
                },
                actions = {
                    IconButton(onClick = { viewModel.clearChat() }) {
                        Icon(Icons.Default.Refresh, contentDescription = "New conversation")
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(
                    containerColor = MaterialTheme.colorScheme.surface
                )
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Messages list
            LazyColumn(
                state = listState,
                modifier = Modifier
                    .weight(1f)
                    .fillMaxWidth(),
                contentPadding = PaddingValues(16.dp),
                verticalArrangement = Arrangement.spacedBy(12.dp)
            ) {
                // Filter out streaming placeholder bubbles (empty content while streaming)
                items(messages.filter { !it.isStreaming || it.content.isNotBlank() }, key = { it.id }) { message ->
                    ChatBubble(message = message)
                }
                
                // Thinking/Loading indicator - show while streaming
                if (isStreaming) {
                    item {
                        ThinkingIndicator(thinking = currentThinking ?: "Processing your request...")
                    }
                }
            }
            
            // Error message
            AnimatedVisibility(visible = error != null) {
                error?.let {
                    Surface(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(horizontal = 16.dp, vertical = 4.dp),
                        color = MaterialTheme.colorScheme.errorContainer,
                        shape = RoundedCornerShape(8.dp)
                    ) {
                        Row(
                            modifier = Modifier.padding(12.dp),
                            verticalAlignment = Alignment.CenterVertically
                        ) {
                            Text(
                                text = it,
                                modifier = Modifier.weight(1f),
                                color = MaterialTheme.colorScheme.onErrorContainer
                            )
                            IconButton(onClick = { viewModel.clearError() }) {
                                Icon(Icons.Default.Close, contentDescription = "Dismiss")
                            }
                        }
                    }
                }
            }
            
            // Input area
            ChatInputArea(
                value = inputText,
                onValueChange = { inputText = it },
                onSend = {
                    if (inputText.isNotBlank()) {
                        viewModel.sendMessage(inputText)
                        inputText = ""
                    }
                },
                isEnabled = !isStreaming,
                modifier = Modifier.padding(16.dp)
            )
        }
    }
}

@Composable
private fun WelcomeCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.primaryContainer
        )
    ) {
        Column(
            modifier = Modifier.padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Text(
                text = "✈️",
                style = MaterialTheme.typography.displayMedium
            )
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Welcome to FlyFun Assistant",
                style = MaterialTheme.typography.titleMedium
            )
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "Ask me about airports, aviation rules, flight planning, and more!",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onPrimaryContainer.copy(alpha = 0.8f)
            )
            
            Spacer(modifier = Modifier.height(16.dp))
            
            // Quick actions
            Row(
                horizontalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                SuggestionChip(
                    onClick = { /* TODO */ },
                    label = { Text("Find airports") }
                )
                SuggestionChip(
                    onClick = { /* TODO */ },
                    label = { Text("Border crossing") }
                )
            }
        }
    }
}

@Composable
private fun ChatBubble(message: UiChatMessage) {
    val isUser = message.role == Role.USER
    
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = if (isUser) Arrangement.End else Arrangement.Start
    ) {
        Box(
            modifier = Modifier
                .fillMaxWidth(0.9f)  // Use 90% of width for wider bubbles on tablets
                .clip(
                    RoundedCornerShape(
                        topStart = 16.dp,
                        topEnd = 16.dp,
                        bottomStart = if (isUser) 16.dp else 4.dp,
                        bottomEnd = if (isUser) 4.dp else 16.dp
                    )
                )
                .background(
                    if (isUser) {
                        // Gradient background matching web UI
                        Brush.linearGradient(
                            colors = listOf(PrimaryGradientStart, PrimaryGradientEnd)
                        )
                    } else {
                        // Light gray for assistant (matching web's #f1f3f5)
                        Brush.linearGradient(
                            colors = listOf(ChatAssistantBubble, ChatAssistantBubble)
                        )
                    }
                )
                .padding(12.dp)
        ) {
            Column {
                if (isUser) {
                    // User messages - plain text
                    Text(
                        text = message.content.ifBlank { "..." },
                        color = androidx.compose.ui.graphics.Color.White
                    )
                } else {
                    // Assistant messages - render as formatted markdown
                    Text(
                        text = parseMarkdown(message.content.ifBlank { "..." }),
                        color = LightOnSurface
                    )
                }
            }
        }
    }
}

@Composable
private fun ThinkingIndicator(thinking: String) {
    // Animated airplane position (0f to 1f)
    val infiniteTransition = rememberInfiniteTransition(label = "airplane")
    val airplaneProgress by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 1f,
        animationSpec = infiniteRepeatable(
            animation = tween(2500, easing = LinearEasing),
            repeatMode = RepeatMode.Restart
        ),
        label = "airplanePosition"
    )
    
    // Simple airplane flying on blue gradient line
    BoxWithConstraints(
        modifier = Modifier
            .fillMaxWidth()
            .height(40.dp)
            .padding(vertical = 8.dp)
    ) {
        val maxWidthPx = constraints.maxWidth.toFloat()
        
        // Flight path background (light gray)
        Box(
            modifier = Modifier
                .align(Alignment.Center)
                .fillMaxWidth()
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(MaterialTheme.colorScheme.outline.copy(alpha = 0.3f))
        )
        
        // Progress trail (gradient blue-purple)
        Box(
            modifier = Modifier
                .align(Alignment.CenterStart)
                .fillMaxWidth(airplaneProgress)
                .height(4.dp)
                .clip(RoundedCornerShape(2.dp))
                .background(
                    Brush.horizontalGradient(
                        colors = listOf(
                            PrimaryGradientStart,
                            PrimaryGradientEnd
                        )
                    )
                )
        )
        
        // Flying airplane
        val offsetPx = (airplaneProgress * (maxWidthPx - 30)).toInt()
        Text(
            text = "✈️",
            fontSize = 20.sp,
            modifier = Modifier
                .offset { IntOffset(offsetPx, 0) }
                .align(Alignment.CenterStart)
        )
    }
}

@Composable
private fun ChatInputArea(
    value: String,
    onValueChange: (String) -> Unit,
    onSend: () -> Unit,
    isEnabled: Boolean,
    modifier: Modifier = Modifier
) {
    Surface(
        modifier = modifier.fillMaxWidth(),
        tonalElevation = 2.dp,
        shape = RoundedCornerShape(24.dp)
    ) {
        Row(
            modifier = Modifier.padding(4.dp),
            verticalAlignment = Alignment.Bottom
        ) {
            OutlinedTextField(
                value = value,
                onValueChange = onValueChange,
                modifier = Modifier.weight(1f),
                placeholder = { Text("Ask about airports, rules...") },
                enabled = isEnabled,
                maxLines = 4,
                keyboardOptions = KeyboardOptions(imeAction = ImeAction.Send),
                keyboardActions = KeyboardActions(onSend = { onSend() }),
                shape = RoundedCornerShape(20.dp),
                colors = OutlinedTextFieldDefaults.colors(
                    focusedBorderColor = MaterialTheme.colorScheme.primary,
                    unfocusedBorderColor = MaterialTheme.colorScheme.outline.copy(alpha = 0.3f)
                )
            )
            
            Spacer(modifier = Modifier.width(8.dp))
            
            FilledIconButton(
                onClick = onSend,
                enabled = isEnabled && value.isNotBlank(),
                modifier = Modifier.size(48.dp)
            ) {
                Icon(
                    imageVector = Icons.Default.Send,
                    contentDescription = "Send"
                )
            }
        }
    }
}

/**
 * Parse markdown text into AnnotatedString with styling
 * Supports: **bold**, *italic*, `inline code`, headers (#), and bullet points
 */
private fun parseMarkdown(text: String): AnnotatedString {
    return buildAnnotatedString {
        var i = 0
        val lines = text.lines()
        
        lines.forEachIndexed { lineIndex, line ->
            var processedLine = line
            
            // Handle headers (# Header)
            when {
                processedLine.startsWith("### ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 16.sp)) {
                        append(processedLine.removePrefix("### "))
                    }
                }
                processedLine.startsWith("## ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 18.sp)) {
                        append(processedLine.removePrefix("## "))
                    }
                }
                processedLine.startsWith("# ") -> {
                    withStyle(SpanStyle(fontWeight = FontWeight.Bold, fontSize = 20.sp)) {
                        append(processedLine.removePrefix("# "))
                    }
                }
                processedLine.startsWith("- ") || processedLine.startsWith("* ") -> {
                    // Bullet points
                    append("  • ")
                    parseInlineMarkdown(this, processedLine.substring(2))
                }
                processedLine.matches(Regex("^\\d+\\.\\s.*")) -> {
                    // Numbered list
                    val num = processedLine.takeWhile { it.isDigit() || it == '.' || it == ' ' }
                    append("  $num")
                    parseInlineMarkdown(this, processedLine.removePrefix(num))
                }
                else -> {
                    parseInlineMarkdown(this, processedLine)
                }
            }
            
            if (lineIndex < lines.size - 1) {
                append("\n")
            }
        }
    }
}

/**
 * Parse inline markdown: **bold**, *italic*, `code`
 */
private fun parseInlineMarkdown(builder: AnnotatedString.Builder, text: String) {
    var remaining = text
    
    while (remaining.isNotEmpty()) {
        when {
            // Bold: **text**
            remaining.startsWith("**") -> {
                val endIndex = remaining.indexOf("**", 2)
                if (endIndex > 2) {
                    builder.withStyle(SpanStyle(fontWeight = FontWeight.Bold)) {
                        append(remaining.substring(2, endIndex))
                    }
                    remaining = remaining.substring(endIndex + 2)
                } else {
                    builder.append("**")
                    remaining = remaining.substring(2)
                }
            }
            // Italic: *text*
            remaining.startsWith("*") && !remaining.startsWith("**") -> {
                val endIndex = remaining.indexOf("*", 1)
                if (endIndex > 1) {
                    builder.withStyle(SpanStyle(fontStyle = FontStyle.Italic)) {
                        append(remaining.substring(1, endIndex))
                    }
                    remaining = remaining.substring(endIndex + 1)
                } else {
                    builder.append("*")
                    remaining = remaining.substring(1)
                }
            }
            // Inline code: `code`
            remaining.startsWith("`") -> {
                val endIndex = remaining.indexOf("`", 1)
                if (endIndex > 1) {
                    builder.withStyle(SpanStyle(
                        fontFamily = FontFamily.Monospace,
                        background = androidx.compose.ui.graphics.Color(0xFFE8E8E8)
                    )) {
                        append(" ${remaining.substring(1, endIndex)} ")
                    }
                    remaining = remaining.substring(endIndex + 1)
                } else {
                    builder.append("`")
                    remaining = remaining.substring(1)
                }
            }
            else -> {
                // Regular text - find next special character
                val nextBold = remaining.indexOf("**").takeIf { it >= 0 } ?: Int.MAX_VALUE
                val nextItalic = remaining.indexOf("*").takeIf { it >= 0 } ?: Int.MAX_VALUE
                val nextCode = remaining.indexOf("`").takeIf { it >= 0 } ?: Int.MAX_VALUE
                val nextSpecial = minOf(nextBold, nextItalic, nextCode)
                
                if (nextSpecial == Int.MAX_VALUE) {
                    builder.append(remaining)
                    remaining = ""
                } else {
                    builder.append(remaining.substring(0, nextSpecial))
                    remaining = remaining.substring(nextSpecial)
                }
            }
        }
    }
}
