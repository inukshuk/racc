#
# format.rb
#
#   Copyright (c) 1999 Minero Aoki <aamine@dp.u-netsurf.ne.jp>
#

require 'amstd/bug'


module Racc

  class RaccFormatter

    def initialize( racc )
      @ruletable  = racc.ruletable
      @tokentable = racc.tokentable
      @statetable = racc.statetable
      @actions    = racc.statetable.actions
      @parser     = racc.parser
      @dsrc       = racc.dsrc
      @debug      = racc.debug
    end

    # abstract output( outf )
  
  end


  class RaccCodeGenerator < RaccFormatter

    def output( out )
      out << "##### racc #{Racc::Version} generates ###\n\n"

      output_reduce_table out
      output_action_table out
      output_goto_table out
      output_token_table out
      output_other out
      if @dsrc then
        out << "Racc_debug_parser = true\n\n"
        out << "Racc_token_to_s_table = [\n"
        out << @tokentable.collect{|tok| "'" + tok.to_s + "'" }.join(",\n")
        out << "]\n\n"
      else
        out << "Racc_debug_parser = false\n\n"
      end
      out << "##### racc system variables end #####\n\n"

      output_actions out
      out << "\n"
    end


    private

    def act2actid( act )
      case act
      when ShiftAction  then act.goto_id
      when ReduceAction then -act.ruleid
      when AcceptAction then @actions.shift_n
      when ErrorAction  then @actions.reduce_n * -1
      else
        bug! "wrong act type #{act.type} in state #{state.stateid}"
      end
    end

    def output_table( out, arr )
      i = 0
      sep = ''
      sep_rest = ','
      buf = ''

      arr.each do |t|
        buf << sep ; sep = sep_rest
        if i == 10 then
          i = 0
          buf << "\n"
          out << buf
          buf = ''
        end
        buf << (t ? sprintf('%6d', t) : '   nil')
        i += 1
      end
      out << buf unless buf.empty?
      out << " ]\n\n"
    end


    def output_reduce_table( out )
      out << "Racc_reduce_table = [\n"
      out << " 0, 0, :racc_error,"
      sep = "\n"
      sep_rest = ",\n"
      @ruletable.each_with_index do |rl, i|
        next if i == 0
        out << sep; sep = sep_rest
        out << sprintf( ' %d, %d, :_reduce_%s',
                        rl.size,
                        rl.simbol.tokenid,
                        rl.action ? i.to_s : 'none' )
      end
      out << " ]\n\n"
      out << "Racc_reduce_n = #{@actions.reduce_n}\n\n"
      out << "Racc_shift_n = #{@actions.shift_n}\n\n"
    end

    def output_token_table( out )
      sep = "\n"
      sep_rest = ",\n"
      out << "Racc_token_table = {"
      @tokentable.each do |tok|
        if tok.terminal? then
          out << sep ; sep = sep_rest
          out << sprintf( " %s => %d", tok.uneval, tok.tokenid )
        end
      end
      out << " }\n\n"
    end

    def output_actions( out )
      @ruletable.each_rule do |rl|
        if str = rl.action then
          i = rl.lineno
          while /\A[ \t\f]*(?:\n|\r\n|\r)/ === str do
            str = $'
            i += 1
          end
          str.sub! /\s+\z/o, ''
=begin
          src = <<SOURCE

 module_eval( <<'.,.,', '%s', %d )
  def _reduce_%d( val, _values, result )
%s
   result
  end
.,.,
SOURCE
=end
          src = <<SOURCE
  def _reduce_%d( val, _values, result )
%s
   result
  end
SOURCE
          out << sprintf( src,
                          # @parser.filename, i - 1,
                          rl.ruleid, str )
        else
          out << sprintf( "\n # reduce %d omitted\n",
                          rl.ruleid )
        end
      end
    end

  end


  class AListTableGenerator < RaccCodeGenerator

    private

    def output_action_table( out )
      disc = []
      tbl = []

      @statetable.each_state do |state|
        disc.push tbl.size
        state.action.each do |tok, act|
          tbl.push tok.tokenid
          tbl.push act2actid( act )
        end
        tbl.push Token::Default_token_id
        tbl.push act2actid( state.defact )
      end

      out << "Racc_action_table = [\n"
      output_table( out, tbl )

      out << "Racc_action_table_ptr = [\n"
      output_table( out, disc )
    end


    def output_goto_table( out )
      disc = []
      tbl = []
      @statetable.each_state do |state|
        if state.nonterm_table.size == 0 then
          disc.push -1
        else
          disc.push tbl.size
          state.nonterm_table.each do |tok, dest|
            tbl.push tok.tokenid
            tbl.push dest.stateid
          end
        end
      end
      tbl.push -1; tbl.push -1   # detect bug

      out << "Racc_goto_table = [\n"
      output_table( out, tbl )

      out << "Racc_goto_table_ptr = [\n"
      output_table( out, disc )
    end

    def output_other( out )
    end

  end


  class IndexTableGenerator < RaccCodeGenerator
  
    private

    def output_action_table( out )
      tbl  = []   # yytable
      chk  = []   # yycheck
      defa = []   # yydefact
      ptr  = []   # yypact
      state = tmp = min = max = i = nil

      @statetable.each_state do |state|
        # default
        defa.push act2actid( state.defact )

        if state.action.empty? then
          ptr.push nil
          next
        end

        tmp = []
        state.action.each do |tok, act|
          tmp[ tok.tokenid ] = act2actid( act )
        end
        max = tmp.size
        0.upto( max ) do |i|
          if tmp[i] then
            min = i
            break
          end
        end

        # check
        i = state.stateid
        (max - min).times { chk.push i }

        # table & pointer
        tmp = tmp[ min, max - min ]
        ptr.push tbl.size - min
        tbl.concat tmp
      end

      out << "Racc_action_table = [\n"
      output_table( out, tbl )

      out << "Racc_action_check = [\n"
      output_table( out, chk )

      out << "Racc_action_default = [\n"
      output_table( out, defa )

      out << "Racc_action_pointer = [\n"
      output_table( out, ptr )
    end


    def output_goto_table( out )
      tbl  = []   # yytable (2)
      chk  = []   # yycheck (2)
      ptr  = []   # yypgoto
      defg = []   # yydefgoto
      state = dflt = tmp = freq = min = max = i = nil

      @tokentable.each_nonterm do |tok|
        tmp = []
        freq = Array.new( @statetable.size, 0 )
        @statetable.each_state do |state|
          st = state.nonterm_table[ tok ]
          if st then
            st = st.stateid
            freq[ st ] += 1
          end
          tmp[ state.stateid ] = st
        end
        tmp.delete_at(-1) until tmp[-1] or tmp.empty?

        max = freq.max
        if max > 1 then
          dflt = freq.index( max )
          tmp.filter {|i| dflt == i ? nil : i }
        else
          dflt = nil
        end

        max = tmp.size
        tmp.each_index do |i|
          if tmp[i] then
            min = i
            break
          end
        end

        # default
        defg.push dflt

        if tmp.compact.empty? then
          ptr.push nil
          next
        end

        # check
        i = tok.tokenid - @tokentable.nt_base
        (max - min).times { chk.push i }

        # table & pointer
        tmp = tmp[ min, max - min ]
        ptr.push tbl.size - min
        tbl.concat tmp
      end
      # tbl.push -1; tbl.push -1   # detect bug

      out << "Racc_goto_table = [\n"
      output_table( out, tbl )

      out << "Racc_goto_check = [\n"
      output_table( out, chk )

      out << "Racc_goto_pointer = [\n"
      output_table( out, ptr )

      out << "Racc_goto_default = [\n"
      output_table( out, defg )
    end

    def output_other( out )
      out << <<S
Racc_nt_base = #{@tokentable.nt_base}

Racc_arg = [
 Racc_action_table,
 Racc_action_check,
 Racc_action_default,
 Racc_action_pointer,
 Racc_goto_table,
 Racc_goto_check,
 Racc_goto_default,
 Racc_goto_pointer,
 Racc_nt_base,
 Racc_reduce_table,
 Racc_token_table,
 Racc_shift_n,
 Racc_reduce_n ]

S
    end

  end


  ###
  ###
  ###

  class VerboseOutputFormatter < RaccFormatter

    def output( out )
      output_conflict out; out << "\n"
      output_rule     out; out << "\n"
      output_token    out; out << "\n"
      output_state    out
    end


    def output_useless( out )
      @tokentable.each do |tok|
        if tok.useless? then
          tok.rules.each do |rl|
            out << sprintf( "rule %d (%s) never reduced\n",
                            rl.ruleid, rl.simbol.to_s )
          end
        end
      end
    end


    def output_conflict( out )
      @statetable.each_state do |state|
        if state.srconf then
          out << sprintf( "state %d contains %d shift/reduce conflicts\n",
                          state.stateid, state.srconf.size )
        end
        if state.rrconf then
          out << sprintf( "state %d contains %d reduce/reduce conflicts\n",
                          state.stateid, state.rrconf.size )
        end
      end
    end


    def output_state( out )
      ptr = nil
      out << "--------- State ---------\n"

      @statetable.each_state do |state|
        out << "\nstate #{state.stateid}\n\n"

        (@debug ? state.closure : state.seed).each do |ptr|
          pointer_out( out, ptr ) if ptr.rule.ruleid != 0 or @debug
        end
        out << "\n"

        action_out( out, state )
      end

      return out
    end

    def pointer_out( out, ptr )
      tmp = sprintf( "%4d) %s :",
                     ptr.rule.ruleid, ptr.rule.simbol.to_s )
      ptr.rule.each_with_index do |tok, idx|
        tmp << ' _' if idx == ptr.index
        tmp << ' ' << tok.to_s
      end
      tmp << ' _' if ptr.reduce?
      tmp << "\n"
      out << tmp
    end

    def action_out( out, state )
      reduce_str = ''

      srconf = state.srconf
      rrconf = state.rrconf

      state.action.each do |tok, act|
        outact out, reduce_str, tok, act
        if srconf and c = srconf[tok] then
          outsrconf reduce_str, c
        end
        if rrconf and c = rrconf[tok] then
          outrrconf reduce_str, c
        end
      end
      outact out, reduce_str, '$default', state.defact

      out << reduce_str
      out << "\n"

      state.nonterm_table.each do |tok, dest|
        out << sprintf( "  %-12s  go to state %d\n", 
                        tok.to_s, dest.stateid )
      end
    end

    def outact( out, r, tok, act )
      case act
      when ShiftAction
        out << sprintf( "  %-12s  shift, and go to state %d\n", 
                        tok.to_s, act.goto_id )
      when ReduceAction
        r << sprintf( "  %-12s  reduce using rule %d (%s)\n",
                      tok.to_s, act.ruleid, act.rule.simbol.to_s )
      when AcceptAction
        out << sprintf( "  %-12s  accept\n", tok.to_s )
      when ErrorAction
        out << sprintf( "  %-12s  error\n", tok.to_s ) if @debug
      else
        bug! "act is not shift/reduce/accept: act=#{act}(#{act.type})"
      end
    end

    def outsrconf( out, confs )
      confs.each do |c|
        r = c.reduce
        out << sprintf( "  %-12s  [reduce using rule %d (%s)]\n",
                        c.shift.to_s, r.ruleid, r.simbol.to_s )
      end
    end

    def outrrconf( out, confs )
      confs.each do |c|
        r = c.low_prec
        out << sprintf( "  %-12s  [reduce using rule %d (%s)]\n",
                        c.token.to_s, r.ruleid, r.simbol.to_s )
      end
    end


    #####


    def output_rule( out )
      out << "-------- Grammar --------\n\n"
      @ruletable.each_rule do |rl|
        if @debug or rl.ruleid != 0 then
          out << sprintf( "rule %d %s: %s\n\n",
            rl.ruleid, rl.simbol.to_s, rl.tokens.join(' ') )
        end
      end

      return out
    end


    #####


    def output_token( out )
      out << "------- Token data -------\n\n"

      out << "**Nonterminals, with rules where they appear\n\n"
      tmp = "**Terminals, with rules where they appear\n\n"

      @tokentable.each do |tok|
        if tok.terminal? then
          terminal_out( tmp, tok )
        else
          nonterminal_out( out, tok )
        end
      end

      out << "\n" << tmp

      return out
    end

    def terminal_out( out, tok )
      tmp = <<SRC
  %s (%d) %s

SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid, tokens2s( tok.locate ) )
    end

    def nonterminal_out( out, tok )
      tmp = <<SRC
  %s (%d)
    on right: %s
    on left : %s
SRC
      out << sprintf( tmp, tok.to_s, tok.tokenid,
                      tokens2s( tok.locate ), tokens2s( tok.rules ) )
    end
    
    def tokens2s( arr )
      tbl = {}
      arr.each do |ptr|
        tbl[ ptr.ruleid ] = true if ptr.ruleid != 0
      end
      tbl.keys.join(' ')
    end

  end

end   # module Racc
